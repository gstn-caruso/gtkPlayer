namespace Music {
    public class LibraryGroup : Object {
        public string title;
        public string artist;
        private Track[] items = {};
        public unowned Track[] tracks { get { return items; } }
        public LibraryGroup (string title, string artist) { this.title = title; this.artist = artist; }
        public void add (Track track) { items += track; }
    }

    public class QueueDrag : Object {
        public string? entry_id;
        public bool cancelled;
        public Track[] tracks;
        public QueueDrag (Track[] tracks, string? id = null) { this.tracks = tracks; entry_id = id; }
    }

    // Recycled by Gtk.ListView/GridView. Callbacks read the currently bound item.
    public class MediaRow : Gtk.Box {
        public static weak Gtk.DragSource? active_drag;
        public static weak QueueDrag? active_payload;
        public Track[] tracks = {};
        public string? entry_id;
        public string? artist;
        public Gtk.Image artwork;
        private Gtk.Label title;
        private Gtk.Label subtitle;
        private Gtk.Label duration;
        private Gtk.Label marker;
        private Gtk.Separator before;
        private Gtk.Separator after;
        public signal void requested (string action);
        public MediaRow (bool card = false, bool queue = false, bool artist_row = false) {
            Object (orientation: Gtk.Orientation.VERTICAL, spacing: 0);
            before = new Gtk.Separator (Gtk.Orientation.HORIZONTAL);
            after = new Gtk.Separator (Gtk.Orientation.HORIZONTAL);
            before.add_css_class ("queue-insertion");
            after.add_css_class ("queue-insertion");
            append (before);
            var body = new Gtk.Box (card ? Gtk.Orientation.VERTICAL : Gtk.Orientation.HORIZONTAL, 12);
            body.margin_top = body.margin_bottom = 10;
            body.margin_start = body.margin_end = 12;
            artwork = new Gtk.Image.from_icon_name ("audio-x-generic-symbolic");
            artwork.pixel_size = card ? 160 : 40;
            artwork.visible = card;
            body.append (artwork);
            var text = new Gtk.Box (Gtk.Orientation.VERTICAL, 3);
            text.hexpand = true;
            title = new Gtk.Label ("");
            title.xalign = 0;
            title.ellipsize = Pango.EllipsizeMode.END;
            title.add_css_class ("heading");
            text.append (title);
            subtitle = new Gtk.Label ("");
            subtitle.xalign = 0;
            subtitle.ellipsize = Pango.EllipsizeMode.END;
            subtitle.add_css_class ("dim-label");
            text.append (subtitle);
            marker = new Gtk.Label ("");
            marker.xalign = 0;
            marker.add_css_class ("caption");
            text.append (marker);
            body.append (text);
            duration = new Gtk.Label ("");
            duration.add_css_class ("numeric");
            duration.visible = !card && !artist_row;
            body.append (duration);
            var menu = new Gtk.MenuButton ();
            menu.icon_name = "view-more-symbolic";
            menu.tooltip_text = queue ? "Acciones de la entrada" : "Acciones de música";
            menu.valign = Gtk.Align.CENTER;
            menu.add_css_class ("flat");
            var popover = new Gtk.Popover ();
            var actions = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            string[] labels = queue ? new string[] {"Reproducir ahora", "Mover arriba", "Mover abajo", "Quitar de la cola"} :
                new string[] {"Agregar a la cola", "Reproducir a continuación", "Reproducir ahora"};
            string[] names = queue ? new string[] {"play-entry", "up", "down", "remove"} : new string[] {"append", "next", "now"};
            for (int i = 0; i < names.length; i++) {
                string action = names[i];
                var button = new Gtk.Button.with_label (labels[i]);
                button.add_css_class ("flat");
                button.clicked.connect (() => { popover.popdown (); requested (action); });
                actions.append (button);
            }
            popover.child = actions;
            menu.popover = popover;
            body.append (menu);
            append (body);
            append (after);
            insertion (0);
            var source = new Gtk.DragSource ();
            source.actions = queue ? Gdk.DragAction.MOVE : Gdk.DragAction.COPY;
            source.drag_begin.connect (() => { active_drag = source; });
            source.drag_end.connect (() => {
                if (active_drag == source) { active_drag = null; active_payload = null; }
            });
            source.prepare.connect ((x, y) => {
                if (tracks.length == 0) return null;
                var data = new QueueDrag (tracks, entry_id);
                active_payload = data;
                Value value = Value (typeof (QueueDrag));
                value.set_object (data);
                return new Gdk.ContentProvider.for_value (value);
            });
            add_controller (source);
        }
        public void bind_track (Track track, string? id = null, string status = "") {
            tracks = {track};
            entry_id = id;
            artist = track.artist;
            title.label = track.title;
            subtitle.label = track.artist;
            duration.label = "%d:%02d".printf ((int) (track.duration / Gst.SECOND / 60), (int) (track.duration / Gst.SECOND % 60));
            marker.label = status;
            marker.visible = status != "";
            tooltip_text = track.title + " — " + track.artist;
            artwork.set_from_icon_name ("audio-x-generic-symbolic");
            insertion (0);
        }
        public void bind_group (LibraryGroup group, bool is_artist = false) {
            tracks = group.tracks;
            entry_id = null;
            artist = group.artist;
            title.label = group.title;
            subtitle.label = is_artist ? (tracks.length == 1 ? "%u pista" : "%u pistas").printf (tracks.length) : group.artist;
            marker.visible = false;
            tooltip_text = group.title + " — " + group.artist;
            artwork.set_from_icon_name (is_artist ? "avatar-default-symbolic" : "audio-x-generic-symbolic");
            if (!is_artist) foreach (var track in tracks) {
                if (track.cover_data == null) continue;
                try { artwork.set_from_paintable (Gdk.Texture.from_bytes (track.cover_data)); break; }
                catch (Error e) { }
            }
            insertion (0);
        }
        public void insertion (int edge) { before.visible = edge < 0; after.visible = edge > 0; }
        public void unbind () { tracks = {}; entry_id = artist = null; artwork.clear (); insertion (0); }
    }
}
