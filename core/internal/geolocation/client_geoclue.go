package geolocation

import (
	"context"
	"fmt"
	"sync"

	"github.com/AvengeMedia/DankMaterialShell/core/internal/log"
	"github.com/AvengeMedia/dankgo/dbusutil"
	"github.com/AvengeMedia/dankgo/syncmap"
	"github.com/godbus/dbus/v5"
)

const (
	dbusGeoClueService   = "org.freedesktop.GeoClue2"
	dbusGeoCluePath      = "/org/freedesktop/GeoClue2"
	dbusGeoClueInterface = dbusGeoClueService

	dbusGeoClueManagerPath      = dbusGeoCluePath + "/Manager"
	dbusGeoClueManagerInterface = dbusGeoClueInterface + ".Manager"
	dbusGeoClueManagerGetClient = dbusGeoClueManagerInterface + ".GetClient"

	dbusGeoClueClientInterface       = dbusGeoClueInterface + ".Client"
	dbusGeoClueClientDesktopId       = dbusGeoClueClientInterface + ".DesktopId"
	dbusGeoClueClientTimeThreshold   = dbusGeoClueClientInterface + ".TimeThreshold"
	dbusGeoClueClientTimeStart       = dbusGeoClueClientInterface + ".Start"
	dbusGeoClueClientTimeStop        = dbusGeoClueClientInterface + ".Stop"
	dbusGeoClueClientLocationUpdated = dbusGeoClueClientInterface + ".LocationUpdated"

	dbusGeoClueLocationInterface = dbusGeoClueInterface + ".Location"
	dbusGeoClueLocationLatitude  = dbusGeoClueLocationInterface + ".Latitude"
	dbusGeoClueLocationLongitude = dbusGeoClueLocationInterface + ".Longitude"

	dbusNameOwnerChangedMember     = "NameOwnerChanged"
	dbusNameOwnerChangedSignalName = "org.freedesktop.DBus." + dbusNameOwnerChangedMember
)

type GeoClueClient struct {
	currLocation  *Location
	locationMutex sync.RWMutex
	seedOnce      sync.Once

	dbusConn *dbus.Conn
	agent    *geoClueAgent
	signals  chan *dbus.Signal

	startOnce  sync.Once
	clientMu   sync.Mutex
	clientPath dbus.ObjectPath

	ctx    context.Context
	cancel context.CancelFunc
	sigWG  sync.WaitGroup

	subscribers syncmap.Map[string, chan Location]
}

func newGeoClueClient() (*GeoClueClient, error) {
	dbusConn, err := dbus.SystemBus()
	if err != nil {
		return nil, fmt.Errorf("system bus connection failed: %w", err)
	}

	ctx, cancel := context.WithCancel(context.Background())
	c := &GeoClueClient{
		ctx:    ctx,
		cancel: cancel,

		dbusConn: dbusConn,
		signals:  make(chan *dbus.Signal, 256),

		currLocation: &Location{
			Latitude:  0.0,
			Longitude: 0.0,
		},
	}

	if agent, err := newGeoClueAgent(ctx, dbusConn); err != nil {
		log.Warnf("GeoClue: %v", err)
	} else {
		c.agent = agent
	}

	c.dbusConn.Signal(c.signals)
	if err := c.dbusConn.AddMatchSignal(ownerMatch...); err != nil {
		log.Warnf("GeoClue: cannot watch for restarts: %v", err)
	}

	if c.agent != nil && c.geoClueRunning() {
		c.agent.register()
	}

	c.sigWG.Go(c.signalLoop)

	return c, nil
}

func (c *GeoClueClient) Close() {
	c.cancel()

	c.sigWG.Wait()

	c.clientMu.Lock()
	if c.clientPath != "" {
		c.dbusConn.Object(dbusGeoClueService, c.clientPath).Call(dbusGeoClueClientTimeStop, 0)
	}
	c.clientMu.Unlock()

	if c.agent != nil {
		c.agent.unexport()
	}

	_ = c.dbusConn.RemoveMatchSignal(ownerMatch...)
	c.dbusConn.RemoveSignal(c.signals)
	close(c.signals)

	c.subscribers.Range(func(key string, ch chan Location) bool {
		close(ch)
		c.subscribers.Delete(key)
		return true
	})
}

func (c *GeoClueClient) Subscribe(id string) chan Location {
	c.ensureStarted()
	ch := make(chan Location, 64)
	c.subscribers.Store(id, ch)
	return ch
}

func (c *GeoClueClient) Unsubscribe(id string) {
	if ch, ok := c.subscribers.LoadAndDelete(id); ok {
		close(ch)
	}
}

func (c *GeoClueClient) geoClueRunning() bool {
	var running bool
	err := c.dbusConn.BusObject().Call("org.freedesktop.DBus.NameHasOwner", 0, dbusGeoClueService).Store(&running)
	return err == nil && running
}

// The client keeps GeoClue resident, so it only starts once something asks for location.
func (c *GeoClueClient) ensureStarted() {
	c.startOnce.Do(func() {
		c.sigWG.Go(func() {
			c.clientMu.Lock()
			defer c.clientMu.Unlock()
			if err := c.startClient(); err != nil {
				log.Warnf("GeoClue: %v", err)
			}
		})
	})
}

func (c *GeoClueClient) setupClient() error {
	managerObj := c.dbusConn.Object(dbusGeoClueService, dbusGeoClueManagerPath)

	if err := managerObj.CallWithContext(c.ctx, dbusGeoClueManagerGetClient, 0).Store(&c.clientPath); err != nil {
		return fmt.Errorf("failed to create GeoClue2 client: %w", err)
	}

	clientObj := c.dbusConn.Object(dbusGeoClueService, c.clientPath)
	if err := clientObj.SetProperty(dbusGeoClueClientDesktopId, dbusGeoClueAgentID); err != nil {
		return fmt.Errorf("failed to set desktop ID: %w", err)
	}

	if err := clientObj.SetProperty(dbusGeoClueClientTimeThreshold, uint(10)); err != nil {
		return fmt.Errorf("failed to set time threshold: %w", err)
	}

	return nil
}

var ownerMatch = []dbus.MatchOption{
	dbus.WithMatchSender("org.freedesktop.DBus"),
	dbus.WithMatchMember(dbusNameOwnerChangedMember),
	dbus.WithMatchArg(0, dbusGeoClueService),
}

func (c *GeoClueClient) locationMatch() []dbus.MatchOption {
	return []dbus.MatchOption{
		dbus.WithMatchObjectPath(c.clientPath),
		dbus.WithMatchInterface(dbusGeoClueClientInterface),
		dbus.WithMatchMember("LocationUpdated"),
	}
}

// Caller holds clientMu.
func (c *GeoClueClient) startClient() error {
	// GetClient blocks until this user has an agent.
	if c.agent != nil {
		c.agent.register()
	}

	if err := c.setupClient(); err != nil {
		c.clientPath = ""
		return err
	}

	if err := c.dbusConn.AddMatchSignal(c.locationMatch()...); err != nil {
		c.clientPath = ""
		return err
	}

	if err := c.dbusConn.Object(dbusGeoClueService, c.clientPath).CallWithContext(c.ctx, dbusGeoClueClientTimeStart, 0).Err; err != nil {
		_ = c.dbusConn.RemoveMatchSignal(c.locationMatch()...)
		c.clientPath = ""
		return err
	}

	return nil
}

func (c *GeoClueClient) restartClient() {
	c.clientMu.Lock()
	defer c.clientMu.Unlock()

	if c.clientPath == "" {
		return
	}

	_ = c.dbusConn.RemoveMatchSignal(c.locationMatch()...)
	c.clientPath = ""

	if err := c.startClient(); err != nil {
		log.Warnf("GeoClue: failed to recreate client after restart: %v", err)
		return
	}
	log.Info("GeoClue: recreated client after restart")
}

func (c *GeoClueClient) signalLoop() {
	for {
		select {
		case <-c.ctx.Done():
			return
		case sig, ok := <-c.signals:
			if !ok {
				return
			}
			if sig == nil {
				continue
			}

			c.handleSignal(sig)
		}
	}
}

func (c *GeoClueClient) handleSignal(sig *dbus.Signal) {
	switch sig.Name {
	case dbusNameOwnerChangedSignalName:
		if len(sig.Body) != 3 {
			return
		}
		if name, _ := sig.Body[0].(string); name != dbusGeoClueService {
			return
		}
		// Re-registering on vanish would re-activate GeoClue after every idle exit.
		if newOwner, _ := sig.Body[2].(string); newOwner != "" {
			if c.agent != nil {
				c.agent.register()
			}
			return
		}
		// A started client keeps GeoClue alive, so vanishing means it crashed or was restarted.
		c.restartClient()
	case dbusGeoClueClientLocationUpdated:
		if len(sig.Body) != 2 {
			return
		}

		newLocationPath, ok := sig.Body[1].(dbus.ObjectPath)
		if !ok {
			return
		}

		if err := c.handleLocationUpdated(newLocationPath); err != nil {
			log.Warnf("GeoClue: Failed to handle location update: %v", err)
			return
		}
	}
}

func (c *GeoClueClient) handleLocationUpdated(path dbus.ObjectPath) error {
	locationObj := c.dbusConn.Object(dbusGeoClueService, path)

	lat, err := locationObj.GetProperty(dbusGeoClueLocationLatitude)
	if err != nil {
		return err
	}

	long, err := locationObj.GetProperty(dbusGeoClueLocationLongitude)
	if err != nil {
		return err
	}

	c.locationMutex.Lock()
	c.currLocation.Latitude = dbusutil.AsOr(lat, 0.0)
	c.currLocation.Longitude = dbusutil.AsOr(long, 0.0)
	c.locationMutex.Unlock()

	c.notifySubscribers()
	return nil
}

func (c *GeoClueClient) notifySubscribers() {
	currentLocation, err := c.GetLocation()
	if err != nil {
		return
	}

	c.subscribers.Range(func(key string, ch chan Location) bool {
		select {
		case ch <- currentLocation:
		default:
			log.Warn("GeoClue: subscriber channel full, dropping update")
		}
		return true
	})
}

func (c *GeoClueClient) SeedLocation(loc Location) {
	c.locationMutex.Lock()
	defer c.locationMutex.Unlock()
	c.currLocation.Latitude = loc.Latitude
	c.currLocation.Longitude = loc.Longitude
}

func (c *GeoClueClient) GetLocation() (Location, error) {
	c.ensureStarted()
	loc := c.currentLocation()
	if loc.Latitude != 0 || loc.Longitude != 0 {
		return loc, nil
	}

	c.seedOnce.Do(func() {
		ipLoc, err := fetchIPLocation()
		if err != nil {
			log.Warnf("GeoClue2 has no fix, IP location seed failed: %v", err)
			return
		}
		log.Info("Seeded GeoClue2 with IP location")
		c.SeedLocation(Location{Latitude: ipLoc.Latitude, Longitude: ipLoc.Longitude})
	})

	return c.currentLocation(), nil
}

func (c *GeoClueClient) currentLocation() Location {
	c.locationMutex.RLock()
	defer c.locationMutex.RUnlock()
	if c.currLocation == nil {
		return Location{}
	}
	return *c.currLocation
}
