package geolocation

import (
	"context"
	"fmt"

	"github.com/AvengeMedia/DankMaterialShell/core/internal/log"
	"github.com/godbus/dbus/v5"
	"github.com/godbus/dbus/v5/introspect"
	"github.com/godbus/dbus/v5/prop"
)

const (
	dbusGeoClueAgentPath        = dbus.ObjectPath(dbusGeoCluePath + "/Agent")
	dbusGeoClueAgentInterface   = dbusGeoClueInterface + ".Agent"
	dbusGeoClueManagerAddAgent  = dbusGeoClueManagerInterface + ".AddAgent"
	dbusGeoClueAgentMaxAccuracy = "MaxAccuracyLevel"
	geoClueAccuracyExact        = uint32(8)
	dbusGeoClueAgentID          = "com.danklinux.dms"
)

type geoClueAgent struct {
	ctx   context.Context
	conn  *dbus.Conn
	props *prop.Properties
}

func newGeoClueAgent(ctx context.Context, conn *dbus.Conn) (*geoClueAgent, error) {
	a := &geoClueAgent{ctx: ctx, conn: conn}

	if err := conn.Export(a, dbusGeoClueAgentPath, dbusGeoClueAgentInterface); err != nil {
		return nil, fmt.Errorf("agent export failed: %w", err)
	}

	props, err := prop.Export(conn, dbusGeoClueAgentPath, prop.Map{
		dbusGeoClueAgentInterface: {
			dbusGeoClueAgentMaxAccuracy: {Value: geoClueAccuracyExact, Emit: prop.EmitTrue},
		},
	})
	if err != nil {
		a.unexport()
		return nil, fmt.Errorf("agent properties export failed: %w", err)
	}
	a.props = props

	node := &introspect.Node{
		Name: string(dbusGeoClueAgentPath),
		Interfaces: []introspect.Interface{
			introspect.IntrospectData,
			prop.IntrospectData,
			{
				Name: dbusGeoClueAgentInterface,
				Methods: []introspect.Method{{
					Name: "AuthorizeApp",
					Args: []introspect.Arg{
						{Name: "desktop_id", Type: "s", Direction: "in"},
						{Name: "req_accuracy_level", Type: "u", Direction: "in"},
						{Name: "authorized", Type: "b", Direction: "out"},
						{Name: "allowed_accuracy_level", Type: "u", Direction: "out"},
					},
				}},
				Properties: props.Introspection(dbusGeoClueAgentInterface),
			},
		},
	}
	if err := conn.Export(introspect.NewIntrospectable(node), dbusGeoClueAgentPath, "org.freedesktop.DBus.Introspectable"); err != nil {
		a.unexport()
		return nil, fmt.Errorf("agent introspection export failed: %w", err)
	}

	return a, nil
}

func (a *geoClueAgent) register() {
	managerObj := a.conn.Object(dbusGeoClueService, dbusGeoClueManagerPath)
	if err := managerObj.CallWithContext(a.ctx, dbusGeoClueManagerAddAgent, 0, dbusGeoClueAgentID).Err; err != nil {
		log.Warnf("GeoClue: agent registration failed, is %q in the [agent] whitelist of geoclue.conf? %v", dbusGeoClueAgentID, err)
		return
	}
	log.Info("GeoClue: registered as location agent")
}

func (a *geoClueAgent) unexport() {
	_ = a.conn.Export(nil, dbusGeoClueAgentPath, dbusGeoClueAgentInterface)
	_ = a.conn.Export(nil, dbusGeoClueAgentPath, "org.freedesktop.DBus.Properties")
	_ = a.conn.Export(nil, dbusGeoClueAgentPath, "org.freedesktop.DBus.Introspectable")
}

func (a *geoClueAgent) maxAccuracy() uint32 {
	return a.props.GetMust(dbusGeoClueAgentInterface, dbusGeoClueAgentMaxAccuracy).(uint32)
}

// ponytail: approves every app up to MaxAccuracyLevel; per-app prompt and permission store come next.
func (a *geoClueAgent) AuthorizeApp(desktopID string, reqAccuracy uint32) (bool, uint32, *dbus.Error) {
	allowed := min(reqAccuracy, a.maxAccuracy())
	log.Debugf("GeoClue: AuthorizeApp %s requested=%d allowed=%d", desktopID, reqAccuracy, allowed)
	return allowed > 0, allowed, nil
}
