namespace Music {
    public class LibraryGroup : Object {
        public string title;
        public string artist;
        public ListStore? albums { get; private set; }
        private Track[] items = {};
        public unowned Track[] tracks { get { return items; } }
        public LibraryGroup (string title, string artist) { this.title = title; this.artist = artist; }
        public void add (Track track) { items += track; }

        public void add_album (LibraryGroup album) {
            if (albums == null) albums = new ListStore (typeof (LibraryGroup));
            albums.append (album);
        }

        public ListModel sidebar_children () {
            if (albums != null) return albums;
            var songs = new ListStore (typeof (Track));
            foreach (var track in items) songs.append (track);
            return songs;
        }

        public Gdk.Texture? cover_artwork () {
            foreach (var track in items) {
                if (track.cover_data == null) continue;
                try { return Gdk.Texture.from_bytes (track.cover_data); }
                catch (Error e) { }
            }
            return null;
        }
    }

    public class LibrarySidebarRow : Gtk.Box {
        public LibraryGroup? artist_group { get; private set; }
        public bool has_portrait { get; private set; }
        private Gtk.Image image;
        private Gtk.MenuButton? photo_button;
        private Gtk.Image? portrait_image;
        private Gtk.Label title;
        private Gtk.Label subtitle;
        public LibrarySidebarRow () {
            Object (orientation: Gtk.Orientation.HORIZONTAL, spacing: 10);
            margin_end = 6;
            margin_top = margin_bottom = 4;
            image = new Gtk.Image ();
            image.set_size_request (40, 40);
            image.valign = Gtk.Align.CENTER;
            image.overflow = Gtk.Overflow.HIDDEN;
            image.add_css_class ("gtkplayer-artwork");
            append (image);
            var text = new Gtk.Box (Gtk.Orientation.VERTICAL, 2);
            text.hexpand = true;
            text.valign = Gtk.Align.CENTER;
            title = new Gtk.Label ("");
            title.xalign = 0;
            title.wrap = true;
            title.wrap_mode = Pango.WrapMode.WORD_CHAR;
            title.ellipsize = Pango.EllipsizeMode.END;
            title.lines = 2;
            text.append (title);
            subtitle = new Gtk.Label ("");
            subtitle.xalign = 0;
            subtitle.ellipsize = Pango.EllipsizeMode.END;
            subtitle.add_css_class ("caption");
            text.append (subtitle);
            append (text);
        }

        public void bind_group (LibraryGroup item, bool root) {
            bool artist_row = item.albums != null;
            artist_group = artist_row ? item : null;
            title.label = item.title;
            subtitle.label = item.artist;
            subtitle.visible = root && !artist_row;
            tooltip_text = artist_row ? item.title : item.title + " — " + item.artist;
            image.visible = true;
            image.name = artist_row ? "sidebar-artist-placeholder" : "sidebar-album-cover";
            if (artist_row) image.add_css_class ("gtkplayer-artist-thumbnail");
            else image.remove_css_class ("gtkplayer-artist-thumbnail");
            image.set_from_icon_name (artist_row ? "avatar-default-symbolic" : "audio-x-generic-symbolic");
            image.pixel_size = 20;
            if (!artist_row) {
                var cover = item.cover_artwork ();
                if (cover != null) show_image (cover);
            }
        }

        public void bind_track (Track track) {
            title.label = track.title;
            tooltip_text = track.title;
            subtitle.visible = image.visible = false;
        }

        public void show_portrait (Gdk.Texture texture, ArtistPhoto photo) {
            if (photo_button == null) {
                portrait_image = new Gtk.Image ();
                portrait_image.name = "sidebar-artist-photo";
                portrait_image.set_size_request (40, 40);
                portrait_image.pixel_size = 40;
                portrait_image.overflow = Gtk.Overflow.HIDDEN;
                portrait_image.add_css_class ("gtkplayer-artwork");
                portrait_image.add_css_class ("gtkplayer-artist-thumbnail");
                photo_button = new Gtk.MenuButton ();
                photo_button.name = "sidebar-photo-credits";
                photo_button.valign = Gtk.Align.CENTER;
                photo_button.add_css_class ("flat");
                photo_button.add_css_class ("gtkplayer-portrait-button");
                photo_button.child = portrait_image;
                insert_child_after (photo_button, image);
            }
            var content = new Gtk.Box (Gtk.Orientation.VERTICAL, 6);
            var author = new Gtk.Label (photo.author);
            author.add_css_class ("heading");
            author.wrap = true;
            author.wrap_mode = Pango.WrapMode.WORD_CHAR;
            author.max_width_chars = 28;
            content.append (author);
            content.append (new Gtk.LinkButton.with_label (photo.license_url, photo.license_name));
            content.append (new Gtk.LinkButton.with_label (photo.source_url, "Wikimedia Commons"));
            var credits = new Gtk.Popover ();
            credits.child = content;
            photo_button.popover = credits;
            photo_button.tooltip_text = "Créditos de la foto";
            photo_button.update_property (Gtk.AccessibleProperty.LABEL, "Créditos de la foto de " + title.label, -1);
            portrait_image.set_from_paintable (texture);
            photo_button.visible = true;
            image.visible = false;
            has_portrait = true;
        }

        private void show_image (Gdk.Texture texture) {
            image.pixel_size = 40;
            image.set_from_paintable (texture);
        }

        public void unbind () {
            artist_group = null;
            has_portrait = false;
            image.clear ();
            if (photo_button != null) {
                photo_button.popover = null;
                photo_button.visible = false;
                portrait_image.clear ();
            }
        }
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
        public bool song_row { get; private set; }
        public Gtk.Image artwork;
        private Gtk.Label title;
        private Gtk.Label subtitle;
        private Gtk.Label duration;
        private Gtk.Label audio_format;
        private Gtk.Label marker;
        private Gtk.Separator before;
        private Gtk.Separator after;
        public signal void requested (string action);
        public MediaRow (bool card = false, bool queue = false) {
            Object (orientation: Gtk.Orientation.VERTICAL, spacing: 0);
            song_row = !card && !queue;
            before = new Gtk.Separator (Gtk.Orientation.HORIZONTAL);
            after = new Gtk.Separator (Gtk.Orientation.HORIZONTAL);
            before.add_css_class ("queue-insertion");
            after.add_css_class ("queue-insertion");
            append (before);
            var body = new Gtk.Box (card ? Gtk.Orientation.VERTICAL : Gtk.Orientation.HORIZONTAL, card ? 6 : 12);
            body.margin_top = body.margin_bottom = card ? 6 : 8;
            body.margin_start = body.margin_end = card ? 6 : 12;
            artwork = new Gtk.Image.from_icon_name ("audio-x-generic-symbolic");
            artwork.pixel_size = card ? 36 : 40;
            artwork.visible = card;
            if (card) {
                body.add_css_class ("gtkplayer-album-tile");
                artwork.set_size_request (144, 144);
                artwork.add_css_class ("gtkplayer-artwork");
                artwork.halign = Gtk.Align.START;
                artwork.overflow = Gtk.Overflow.HIDDEN;
                body.append (artwork);
            }
            var metadata = card ? new Gtk.Box (Gtk.Orientation.HORIZONTAL, 2) : body;
            if (card) body.append (metadata);
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
            text.append (subtitle);
            marker = new Gtk.Label ("");
            marker.xalign = 0;
            marker.add_css_class ("caption");
            text.append (marker);
            metadata.append (text);
            duration = new Gtk.Label ("");
            duration.add_css_class ("numeric");
            duration.visible = !card;
            duration.xalign = 1;
            var details = new Gtk.Box (Gtk.Orientation.VERTICAL, 2);
            details.valign = Gtk.Align.CENTER;
            details.append (duration);
            audio_format = new Gtk.Label ("");
            audio_format.name = "track-format";
            audio_format.xalign = 1;
            audio_format.max_width_chars = 12;
            audio_format.ellipsize = Pango.EllipsizeMode.END;
            audio_format.add_css_class ("caption");
            audio_format.add_css_class ("dim-label");
            audio_format.visible = !card && !queue;
            details.append (audio_format);
            metadata.append (details);
            var menu = new Gtk.MenuButton ();
            menu.icon_name = "view-more-symbolic";
            menu.tooltip_text = queue ? "Acciones de la entrada" : "Acciones de música";
            menu.update_property (Gtk.AccessibleProperty.LABEL, menu.tooltip_text, -1);
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
            metadata.append (menu);
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
            audio_format.label = track.codec;
            audio_format.tooltip_text = track.audio_description ();
            audio_format.update_property (Gtk.AccessibleProperty.DESCRIPTION, track.audio_description (), -1);
            set_status (status);
            tooltip_text = track.title + " — " + track.artist + "\n" + track.audio_description ();
            artwork.set_from_icon_name ("audio-x-generic-symbolic");
            insertion (0);
        }
        public void bind_group (LibraryGroup group) {
            tracks = group.tracks;
            entry_id = null;
            artist = group.artist;
            title.label = group.title;
            subtitle.label = group.artist;
            marker.visible = false;
            tooltip_text = group.title + " — " + group.artist;
            artwork.set_from_icon_name ("audio-x-generic-symbolic");
            artwork.pixel_size = 36;
            var cover = group.cover_artwork ();
            if (cover != null) {
                artwork.set_from_paintable (cover);
                artwork.pixel_size = 144;
            }
            insertion (0);
        }
        public void insertion (int edge) { before.visible = edge < 0; after.visible = edge > 0; }
        public void set_status (string status, bool current = false) {
            marker.label = status;
            marker.visible = status != "";
            if (current) title.add_css_class ("accent");
            else title.remove_css_class ("accent");
        }
        public void unbind () { tracks = {}; entry_id = artist = null; artwork.clear (); insertion (0); }
    }
}
