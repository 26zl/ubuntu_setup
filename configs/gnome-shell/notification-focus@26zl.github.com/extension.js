// Clicking a notification raises its app even when the app ignores the
// activation token GNOME Shell hands it (portal libnotify, terminals, scripts),
// then completes the unused token so the busy cursor stops. Only running apps
// are raised; nothing is launched, because the click may be starting the app.

import GLib from 'gi://GLib';
import Shell from 'gi://Shell';

import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';

// time an app gets to raise itself with its token before the shell does it
const RAISE_DELAY_MS = 600;
// a multi-window app may still use its token this long to pick the right window
const TOKEN_GRACE_MS = 2000;
// focus requests from the clicked app are granted this long after the click
const ATTENTION_GRACE_MS = 5000;
// a startup sequence this young at click time is the click's activation token
const FRESH_TOKEN_MS = 500;

export default class NotificationFocusExtension extends Extension {
    enable() {
        this._timeouts = new Set();
        this._tokenSeen = new Map();
        this._clicked = null;
        this._tracker = Shell.WindowTracker.get_default();

        this._tracker.connectObject('startup-sequence-changed', () => this._trackTokens(), this);
        Main.messageTray.connectObject('source-added',
            (_tray, source) => this._watchSource(source), this);
        for (const source of Main.messageTray.getSources())
            this._watchSource(source);
        global.display.connectObject(
            'window-demands-attention', (_display, window) => this._onAttention(window),
            'window-marked-urgent', (_display, window) => this._onAttention(window),
            this);
    }

    disable() {
        for (const id of this._timeouts)
            GLib.source_remove(id);
        this._tracker.disconnectObject(this);
        Main.messageTray.disconnectObject(this);
        for (const source of Main.messageTray.getSources()) {
            source.disconnectObject(this);
            for (const notification of source.notifications)
                notification.disconnectObject(this);
        }
        global.display.disconnectObject(this);
        this._timeouts = null;
        this._tokenSeen = null;
        this._clicked = null;
        this._tracker = null;
    }

    _watchSource(source) {
        source.connectObject('notification-added',
            (_source, notification) => this._watchNotification(source, notification), this);
        for (const notification of source.notifications)
            this._watchNotification(source, notification);
    }

    _watchNotification(source, notification) {
        // 'activated' is a click on the notification itself, not on its buttons
        notification.connectObject('activated', () => this._onActivated(source), this);
    }

    // remember when each startup sequence (activation token) first appeared
    _trackTokens() {
        const now = GLib.get_monotonic_time();
        const live = new Set();
        for (const sequence of this._tracker.get_startup_sequences()) {
            const id = sequence.get_id();
            live.add(id);
            if (!this._tokenSeen.has(id))
                this._tokenSeen.set(id, now);
        }
        for (const id of [...this._tokenSeen.keys()]) {
            if (!live.has(id))
                this._tokenSeen.delete(id);
        }
    }

    _onActivated(source) {
        // FdoNotificationDaemonSource keeps the app in .app, GtkNotificationDaemonAppSource in ._app
        const app = source.app ?? source._app ?? null;

        // the notification daemon created the click's token just before 'activated'
        this._trackTokens();
        const now = GLib.get_monotonic_time();
        const tokens = [...this._tokenSeen]
            .filter(([, seen]) => now - seen < FRESH_TOKEN_MS * 1000)
            .map(([id]) => id);

        this._clicked = {app, until: now + ATTENTION_GRACE_MS * 1000};

        this._after(RAISE_DELAY_MS, () => {
            const running = app?.get_state() === Shell.AppState.RUNNING;
            if (running && this._tracker.focus_app !== app)
                app.activate();
            // with one window there is nothing left for a late token to choose
            if (!app || (running && app.get_n_windows() <= 1))
                this._complete(tokens);
        });
        this._after(TOKEN_GRACE_MS, () => {
            // an app that is still starting keeps its token for its first window
            if (!app || app.get_state() === Shell.AppState.RUNNING)
                this._complete(tokens);
        });
    }

    // An app that raises itself without a valid token only gets "demands
    // attention". Grant it when it is the app that was just clicked.
    _onAttention(window) {
        const clicked = this._clicked;
        if (!clicked?.app || GLib.get_monotonic_time() > clicked.until)
            return;
        if (this._tracker.get_window_app(window) !== clicked.app)
            return;
        Main.activateWindow(window);
    }

    // completing an unused token stops the busy cursor
    _complete(tokens) {
        for (const sequence of this._tracker.get_startup_sequences()) {
            if (tokens.includes(sequence.get_id()) && !sequence.get_completed())
                sequence.complete();
        }
    }

    _after(ms, callback) {
        const id = GLib.timeout_add(GLib.PRIORITY_DEFAULT, ms, () => {
            this._timeouts.delete(id);
            callback();
            return GLib.SOURCE_REMOVE;
        });
        this._timeouts.add(id);
    }
}
