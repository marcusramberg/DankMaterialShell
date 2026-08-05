package network

import (
	"sync"

	"github.com/AvengeMedia/DankMaterialShell/core/pkg/syncmap"
)

// CellularBackend is a supplementary backend that manages cellular (mobile data)
// connections via ModemManager. It coexists with the primary network Backend
// (NetworkManager/iwd/networkd) rather than replacing it: a system can have
// both WiFi/Ethernet AND a WWAN modem active at the same time.
type CellularBackend interface {
	Initialize() error
	Close()

	GetState() (*CellularState, error)

	StartMonitoring(onStateChange func()) error
	StopMonitoring()
}

type CellularStatus string

const (
	CellularDisconnected CellularStatus = "disconnected"
	CellularConnecting   CellularStatus = "connecting"
	CellularConnected    CellularStatus = "connected"
	CellularSearching    CellularStatus = "searching"
	CellularUnavailable  CellularStatus = "unavailable"
)

type ModemDevice struct {
	Path         string `json:"path"`
	Manufacturer string `json:"manufacturer,omitempty"`
	Model        string `json:"model,omitempty"`
	Firmware     string `json:"firmware,omitempty"`
	IMEI         string `json:"imei,omitempty"`
	SIMICCID     string `json:"simIccid,omitempty"`
	SIMState     string `json:"simState,omitempty"`
	Operator     string `json:"operator,omitempty"`
	OperatorCode string `json:"operatorCode,omitempty"`
	Signal       uint8  `json:"signal,omitempty"`
	AccessTech   string `json:"accessTech,omitempty"`
	State        string `json:"state"`
	Enabled      bool   `json:"enabled"`
	Connected    bool   `json:"connected"`
	IPv4         string `json:"ipv4,omitempty"`
}

type CellularState struct {
	Available bool           `json:"available"`
	Enabled   bool           `json:"enabled"`
	Connected bool           `json:"connected"`
	Status    CellularStatus `json:"status"`
	Modems    []ModemDevice  `json:"modems"`
}

type CellularManager struct {
	backend     CellularBackend
	state       *CellularState
	stateMutex  sync.RWMutex
	subscribers syncmap.Map[string, chan CellularState]
}

func NewCellularManager(backend CellularBackend) *CellularManager {
	return &CellularManager{
		backend: backend,
		state:   &CellularState{Available: false},
	}
}

func (m *CellularManager) syncState() error {
	state, err := m.backend.GetState()
	if err != nil {
		return err
	}
	m.stateMutex.Lock()
	m.state = state
	m.stateMutex.Unlock()
	return nil
}

func (m *CellularManager) onBackendStateChange() {
	if err := m.syncState(); err != nil {
		return
	}
	m.notify()
}

func (m *CellularManager) notify() {
	m.stateMutex.RLock()
	s := *m.state
	s.Modems = append([]ModemDevice(nil), m.state.Modems...)
	m.stateMutex.RUnlock()

	m.subscribers.Range(func(key string, ch chan CellularState) bool {
		select {
		case ch <- s:
		default:
		}
		return true
	})
}

func (m *CellularManager) GetState() CellularState {
	m.stateMutex.RLock()
	defer m.stateMutex.RUnlock()
	s := *m.state
	s.Modems = append([]ModemDevice(nil), m.state.Modems...)
	return s
}

func (m *CellularManager) Subscribe(id string) chan CellularState {
	ch := make(chan CellularState, 16)
	m.subscribers.Store(id, ch)
	return ch
}

func (m *CellularManager) Unsubscribe(id string) {
	if val, ok := m.subscribers.LoadAndDelete(id); ok {
		close(val)
	}
}

func (m *CellularManager) Start() error {
	if err := m.backend.Initialize(); err != nil {
		return err
	}
	if err := m.syncState(); err != nil {
		return err
	}
	return m.backend.StartMonitoring(m.onBackendStateChange)
}

func (m *CellularManager) Close() {
	if m.backend != nil {
		m.backend.Close()
	}
	m.subscribers.Range(func(key string, ch chan CellularState) bool {
		close(ch)
		m.subscribers.Delete(key)
		return true
	})
}
