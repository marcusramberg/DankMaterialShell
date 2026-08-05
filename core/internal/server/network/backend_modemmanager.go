package network

import (
	"fmt"
	"sync"

	"github.com/AvengeMedia/DankMaterialShell/core/internal/log"
	"github.com/godbus/dbus/v5"
)

const (
	mmBusName    = "org.freedesktop.ModemManager1"
	mmRootPath   = "/org/freedesktop/ModemManager1"
	mmIface      = "org.freedesktop.ModemManager1"
	mmIfaceModem = "org.freedesktop.ModemManager1.Modem"
	mmIfaceSim   = "org.freedesktop.ModemManager1.Sim"
	mmIface3gpp  = "org.freedesktop.ModemManager1.Modem.Modem3gpp"
	mmIfaceProps = "org.freedesktop.DBus.Properties"

	// Modem.State enum values
	mmStateFailed        = 0
	mmStateUnknown       = 1
	mmStateInitializing  = 2
	mmStateLocked        = 3
	mmStateDisabled      = 4
	mmStateDisabledLock  = 5
	mmStateEnabling      = 6
	mmStateEnabled       = 7
	mmStateSearching     = 8
	mmStateRegistered    = 9
	mmStateDisconnecting = 10
	mmStateConnecting    = 11
	mmStateConnected     = 12
)

type ModemManagerBackend struct {
	conn          *dbus.Conn
	signals       chan *dbus.Signal
	sigWG         sync.WaitGroup
	stopChan      chan struct{}
	onStateChange func()

	modemPaths []dbus.ObjectPath

	state      *CellularState
	stateMutex sync.RWMutex
}

func NewModemManagerBackend() *ModemManagerBackend {
	return &ModemManagerBackend{
		stopChan: make(chan struct{}),
		state:    &CellularState{Available: false},
	}
}

func (b *ModemManagerBackend) Initialize() error {
	conn, err := dbus.ConnectSystemBus()
	if err != nil {
		return fmt.Errorf("connect system bus: %w", err)
	}
	b.conn = conn

	if err := b.discoverModems(); err != nil {
		conn.Close()
		return fmt.Errorf("discover modems: %w", err)
	}

	if err := b.refreshState(); err != nil {
		conn.Close()
		return fmt.Errorf("read cellular state: %w", err)
	}

	return nil
}

func (b *ModemManagerBackend) Close() {
	b.StopMonitoring()
	if b.conn != nil {
		b.conn.Close()
	}
}

func (b *ModemManagerBackend) discoverModems() error {
	obj := b.conn.Object(mmBusName, mmRootPath)
	if v, err := obj.GetProperty(mmIface + ".Modems"); err == nil {
		if paths, ok := v.Value().([]dbus.ObjectPath); ok {
			b.modemPaths = paths
			return nil
		}
	}

	// Fall back to GetManagedObjects if the Modems property is unavailable.
	var objects map[dbus.ObjectPath]map[string]map[string]dbus.Variant
	if err := obj.Call("org.freedesktop.DBus.ObjectManager.GetManagedObjects", 0).Store(&objects); err != nil {
		return fmt.Errorf("get managed objects: %w", err)
	}
	for path, ifaces := range objects {
		if _, ok := ifaces[mmIfaceModem]; ok {
			b.modemPaths = append(b.modemPaths, path)
		}
	}
	return nil
}

func (b *ModemManagerBackend) GetState() (*CellularState, error) {
	b.stateMutex.RLock()
	defer b.stateMutex.RUnlock()
	s := *b.state
	s.Modems = append([]ModemDevice(nil), b.state.Modems...)
	return &s, nil
}

func (b *ModemManagerBackend) refreshState() error {
	if len(b.modemPaths) == 0 {
		b.stateMutex.Lock()
		b.state.Available = false
		b.state.Enabled = false
		b.state.Connected = false
		b.state.Status = CellularUnavailable
		b.state.Modems = []ModemDevice{}
		b.stateMutex.Unlock()
		return nil
	}

	var modems []ModemDevice
	anyEnabled := false
	anyConnected := false
	status := CellularDisconnected

	for _, path := range b.modemPaths {
		md, err := b.readModem(path)
		if err != nil {
			log.Warnf("modemmanager: failed to read modem %s: %v", path, err)
			continue
		}
		modems = append(modems, md)
		if md.Enabled {
			anyEnabled = true
		}
		if md.Connected {
			anyConnected = true
		}
	}

	if anyConnected {
		status = CellularConnected
	}

	b.stateMutex.Lock()
	b.state.Available = true
	b.state.Enabled = anyEnabled
	b.state.Connected = anyConnected
	b.state.Status = status
	b.state.Modems = modems
	b.stateMutex.Unlock()

	return nil
}

func (b *ModemManagerBackend) readModem(path dbus.ObjectPath) (ModemDevice, error) {
	obj := b.conn.Object(mmBusName, path)
	var md ModemDevice
	md.Path = string(path)

	if v, err := obj.GetProperty(mmIfaceModem + ".State"); err != nil {
		return md, err
	} else if st, ok := v.Value().(uint32); ok {
		md.State = mmStateString(st)
		md.Enabled = st >= mmStateEnabling
		md.Connected = st == mmStateConnected
	}

	if v, err := obj.GetProperty(mmIfaceModem + ".Manufacturer"); err == nil {
		if s, ok := v.Value().(string); ok {
			md.Manufacturer = s
		}
	}
	if v, err := obj.GetProperty(mmIfaceModem + ".Model"); err == nil {
		if s, ok := v.Value().(string); ok {
			md.Model = s
		}
	}
	if v, err := obj.GetProperty(mmIfaceModem + ".FirmwareVersion"); err == nil {
		if s, ok := v.Value().(string); ok {
			md.Firmware = s
		}
	}
	if v, err := obj.GetProperty(mmIfaceModem + ".EquipmentIdentifier"); err == nil {
		if s, ok := v.Value().(string); ok {
			md.IMEI = s
		}
	}
	if v, err := obj.GetProperty(mmIfaceModem + ".SignalQuality"); err == nil {
		if tuple, ok := v.Value().([]any); ok && len(tuple) == 2 {
			if pct, ok := tuple[0].(uint32); ok {
				md.Signal = uint8(pct)
			}
		}
	}
	if v, err := obj.GetProperty(mmIfaceModem + ".AccessTechnologies"); err == nil {
		if t, ok := v.Value().(uint32); ok {
			md.AccessTech = mmAccessTechString(t)
		}
	}

	// SIM details
	var simPath dbus.ObjectPath
	if v, err := obj.GetProperty(mmIfaceModem + ".Sim"); err == nil {
		if p, ok := v.Value().(dbus.ObjectPath); ok {
			simPath = p
		}
	}
	if simPath != "" && simPath != "/" {
		simObj := b.conn.Object(mmBusName, simPath)
		if v, err := simObj.GetProperty(mmIfaceSim + ".SimIdentifier"); err == nil {
			if s, ok := v.Value().(string); ok {
				md.SIMICCID = s
			}
		}
		if v, err := simObj.GetProperty(mmIfaceSim + ".State"); err == nil {
			if st, ok := v.Value().(uint32); ok {
				md.SIMState = mmSimStateString(st)
			}
		}
		if v, err := simObj.GetProperty(mmIfaceSim + ".OperatorName"); err == nil {
			if s, ok := v.Value().(string); ok {
				md.Operator = s
			}
		}
		if v, err := simObj.GetProperty(mmIfaceSim + ".OperatorCode"); err == nil {
			if s, ok := v.Value().(string); ok {
				md.OperatorCode = s
			}
		}
	}

	// Operator may also come from the 3gpp interface (registered network)
	if v, err := obj.GetProperty(mmIface3gpp + ".OperatorName"); err == nil {
		if s, ok := v.Value().(string); ok && s != "" {
			md.Operator = s
		}
	}

	return md, nil
}

func (b *ModemManagerBackend) StartMonitoring(onStateChange func()) error {
	b.onStateChange = onStateChange

	signals := make(chan *dbus.Signal, 128)
	b.signals = signals
	b.conn.Signal(signals)

	if err := b.conn.AddMatchSignal(
		dbus.WithMatchInterface(mmIfaceProps),
		dbus.WithMatchMember("PropertiesChanged"),
	); err != nil {
		b.conn.RemoveSignal(signals)
		return err
	}

	b.sigWG.Add(1)
	go b.signalLoop(signals)
	return nil
}

func (b *ModemManagerBackend) StopMonitoring() {
	if b.signals != nil {
		b.conn.RemoveSignal(b.signals)
	}
	select {
	case <-b.stopChan:
	default:
		close(b.stopChan)
	}
	b.sigWG.Wait()
}

func (b *ModemManagerBackend) signalLoop(signals chan *dbus.Signal) {
	defer b.sigWG.Done()
	for {
		select {
		case <-b.stopChan:
			return
		case _, ok := <-signals:
			if !ok {
				return
			}
			// PropertiesChanged on any modem; re-read everything.
			if err := b.refreshState(); err != nil {
				log.Warnf("modemmanager: refresh after signal: %v", err)
				continue
			}
			if b.onStateChange != nil {
				b.onStateChange()
			}
		}
	}
}

func mmStateString(s uint32) string {
	switch s {
	case mmStateFailed:
		return "failed"
	case mmStateUnknown:
		return "unknown"
	case mmStateInitializing:
		return "initializing"
	case mmStateLocked:
		return "locked"
	case mmStateDisabled, mmStateDisabledLock:
		return "disabled"
	case mmStateEnabling:
		return "enabling"
	case mmStateEnabled:
		return "enabled"
	case mmStateSearching:
		return "searching"
	case mmStateRegistered:
		return "registered"
	case mmStateDisconnecting:
		return "disconnecting"
	case mmStateConnecting:
		return "connecting"
	case mmStateConnected:
		return "connected"
	default:
		return "unknown"
	}
}

func mmSimStateString(s uint32) string {
	switch s {
	case 0:
		return "unknown"
	case 1:
		return "absent"
	case 2:
		return "not_initialized"
	case 3:
		return "not_ready"
	case 4:
		return "sim_locked"
	case 5:
		return "ready"
	case 6:
		return "sim_not_locked"
	case 7:
		return "sim_pin_required"
	case 8:
		return "sim_puk_required"
	case 9:
		return "sim_network_personalization"
	case 10:
		return "sim_pin2_required"
	case 11:
		return "sim_puk2_required"
	default:
		return "unknown"
	}
}

func mmAccessTechString(t uint32) string {
	names := []string{
		"unknown", "gsm", "gsm_compact", "gprs", "edge", "umts",
		"hsdpa", "hsupa", "hspa", "hspa_plus", "lte", "lte_advanced", "5gnr",
	}
	var out string
	for i, name := range names {
		if t&(1<<i) != 0 {
			if out != "" {
				out += ","
			}
			out += name
		}
	}
	if out == "" {
		return "unknown"
	}
	return out
}
