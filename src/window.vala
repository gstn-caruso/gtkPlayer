namespace Music {
    public class Window : Adw.ApplicationWindow {
        public uint track_count { get { return library.length; } }
        public bool loading { get; private set; default = false; }
        private string config_path;
        private Track[] library = {};
        private Track[] visible_tracks = {};
        private string[] group_keys = {};
        private PlayQueue queue = new PlayQueue ();
        private Player player;
        private Cancellable? scan_cancel;
        private Gtk.Entry location;
        private Gtk.Button load_button;
        private Gtk.Button cancel_button;
        private Gtk.Button play_button;
        private Gtk.Spinner spinner;
        private Gtk.Label status;
        private Gtk.Label heading;
        private Gtk.Label info;
        private Gtk.Label now_playing;
        private Gtk.Label clock;
        private Gtk.ListBox groups;
        private Gtk.ListBox tracks;
        private Gtk.ListBox queue_list;
        private Gtk.DropDown grouping;
        private Gtk.Scale position_scale;
        private uint ticker;
        private bool updating_position;
        private bool closed;

        public Window (Gtk.Application app, string config_path, Gst.Element? sink = null) {
            Object (application: app, title: "Música · GTK Player", default_width: 1280, default_height: 800);
            this.config_path = config_path;
            player = new Player (queue, sink);
            build_ui ();
            player.changed.connect (update_player);
            player.failure.connect ((message) => { status.label = "No se pudo reproducir: " + message; });
            player.finished.connect (() => { status.label = "Fin de la cola"; });
            ticker = Timeout.add (500, () => {
                double duration = player.duration ();
                updating_position = true;
                position_scale.set_range (0, duration > 0 ? duration : 1);
                position_scale.set_value (player.position ());
                position_scale.sensitive = duration > 0;
                updating_position = false;
                clock.label = time_text (player.position ()) + " / " + time_text (duration);
                return Source.CONTINUE;
            });
            close_request.connect (() => {
                closed = true;
                if (scan_cancel != null) scan_cancel.cancel ();
                player.shutdown ();
                if (ticker != 0) { Source.remove (ticker); ticker = 0; }
                return false;
            });
        }

        private void build_ui () {
            var root = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            var header = new Adw.HeaderBar ();
            header.title_widget = new Gtk.Label ("Tu música, en tu red");
            root.append (header);
            var source = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
            source.margin_start = source.margin_end = 16;
            source.margin_bottom = 12;
            location = new Gtk.Entry ();
            location.name = "location";
            location.hexpand = true;
            location.placeholder_text = "Carpeta local, file:// o smb://";
            location.text = new LocationSettings (config_path).load ();
            source.append (location);
            var browse = new Gtk.Button.from_icon_name ("folder-open-symbolic");
            browse.tooltip_text = "Elegir carpeta";
            browse.clicked.connect (() => { choose_folder.begin (); });
            source.append (browse);
            load_button = new Gtk.Button.with_label ("Cargar");
            load_button.name = "load";
            load_button.add_css_class ("suggested-action");
            load_button.clicked.connect (() => { load_library.begin (location.text); });
            location.activate.connect (() => { if (!loading) load_library.begin (location.text); });
            source.append (load_button);
            cancel_button = new Gtk.Button.with_label ("Cancelar");
            cancel_button.name = "cancel";
            cancel_button.sensitive = false;
            cancel_button.clicked.connect (() => { if (scan_cancel != null) scan_cancel.cancel (); });
            source.append (cancel_button);
            spinner = new Gtk.Spinner ();
            source.append (spinner);
            root.append (source);
            status = text_label ("Elegí una ubicación y pulsá Cargar. No se accede a la red al iniciar.");
            status.margin_start = status.margin_end = 16;
            status.margin_bottom = 12;
            status.wrap = true;
            status.selectable = true;
            root.append (status);

            var left = new Gtk.Box (Gtk.Orientation.VERTICAL, 10);
            left.name = "library";
            left.width_request = 220;
            left.margin_start = left.margin_end = 12;
            left.append (title_label ("Tu biblioteca"));
            grouping = new Gtk.DropDown.from_strings ({"Álbumes", "Artistas"});
            grouping.notify["selected"].connect (() => { rebuild_groups (); });
            left.append (grouping);
            groups = new Gtk.ListBox ();
            groups.add_css_class ("navigation-sidebar");
            groups.row_selected.connect ((row) => {
                if (row == null) return;
                int index = row.get_index ();
                if (index == 0) show_tracks (library, "Todas las pistas");
                else if (index - 1 < group_keys.length) {
                    string key = group_keys[index - 1];
                    Track[] selected = {};
                    foreach (var track in library)
                        if (group_key (track) == key) selected += track;
                    show_tracks (selected, key);
                }
            });
            left.append (scroll (groups));

            var center = new Gtk.Box (Gtk.Orientation.VERTICAL, 12);
            center.name = "tracks";
            center.hexpand = true;
            center.margin_start = center.margin_end = 20;
            var summary = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 20);
            summary.margin_top = summary.margin_bottom = 20;
            var cover = new Gtk.Image.from_icon_name ("audio-x-generic-symbolic");
            cover.pixel_size = 96;
            summary.append (cover);
            var summary_text = new Gtk.Box (Gtk.Orientation.VERTICAL, 8);
            summary_text.valign = Gtk.Align.CENTER;
            heading = title_label ("Tu biblioteca está vacía");
            heading.add_css_class ("title-1");
            summary_text.append (heading);
            summary_text.append (text_label ("Seleccioná un álbum o artista.\nDoble clic en una pista para reproducir."));
            summary.append (summary_text);
            center.append (summary);
            tracks = new Gtk.ListBox ();
            tracks.add_css_class ("boxed-list");
            tracks.activate_on_single_click = false;
            tracks.row_activated.connect ((row) => {
                queue.replace (visible_tracks);
                if (queue.select (row.get_index ())) { player.stop (); player.play (); refresh_queue (); }
            });
            center.append (scroll (tracks));

            var right = new Gtk.Box (Gtk.Orientation.VERTICAL, 10);
            right.name = "details";
            right.width_request = 240;
            right.margin_start = right.margin_end = 12;
            var stack = new Gtk.Stack ();
            stack.vexpand = true;
            var tabs = new Gtk.StackSwitcher ();
            tabs.stack = stack;
            tabs.halign = Gtk.Align.CENTER;
            right.append (tabs);
            info = text_label ("Sin reproducción\n\nLos datos de la pista aparecerán aquí.");
            info.wrap = true;
            info.selectable = true;
            stack.add_titled (scroll (info), "data", "Datos");
            queue_list = new Gtk.ListBox ();
            queue_list.activate_on_single_click = false;
            queue_list.row_activated.connect ((row) => {
                if (queue.select (row.get_index ())) { player.stop (); player.play (); }
            });
            stack.add_titled (scroll (queue_list), "queue", "Cola");
            right.append (stack);
            var inner = new Gtk.Paned (Gtk.Orientation.HORIZONTAL);
            inner.start_child = center;
            inner.end_child = right;
            inner.resize_end_child = false;
            inner.shrink_start_child = inner.shrink_end_child = false;
            var panels = new Gtk.Paned (Gtk.Orientation.HORIZONTAL);
            panels.start_child = left;
            panels.end_child = inner;
            panels.resize_start_child = false;
            panels.shrink_start_child = false;
            panels.vexpand = true;
            root.append (panels);
            root.append (new Gtk.Separator (Gtk.Orientation.HORIZONTAL));
            root.append (build_controls ());
            content = root;
        }

        private Gtk.Widget build_controls () {
            var bar = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 16);
            bar.name = "controls";
            bar.margin_start = bar.margin_end = 20;
            bar.margin_top = bar.margin_bottom = 16;
            now_playing = text_label ("Nada en reproducción");
            now_playing.width_request = 220;
            now_playing.ellipsize = Pango.EllipsizeMode.END;
            bar.append (now_playing);
            var middle = new Gtk.Box (Gtk.Orientation.VERTICAL, 4);
            middle.hexpand = true;
            var buttons = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 12);
            buttons.halign = Gtk.Align.CENTER;
            var previous = icon_button ("media-skip-backward-symbolic", "Anterior");
            previous.clicked.connect (() => { player.previous (); });
            buttons.append (previous);
            play_button = icon_button ("media-playback-start-symbolic", "Reproducir o pausar");
            play_button.clicked.connect (() => {
                if (player.state == Gst.State.PLAYING) player.pause ();
                else {
                    if (queue.current == null && visible_tracks.length > 0) {
                        queue.replace (visible_tracks);
                        queue.select (0);
                        refresh_queue ();
                    }
                    player.play ();
                }
            });
            buttons.append (play_button);
            var next = icon_button ("media-skip-forward-symbolic", "Siguiente");
            next.clicked.connect (() => { player.next (); });
            buttons.append (next);
            middle.append (buttons);
            position_scale = new Gtk.Scale.with_range (Gtk.Orientation.HORIZONTAL, 0, 1, 1);
            position_scale.draw_value = false;
            position_scale.sensitive = false;
            position_scale.change_value.connect ((type, value) => {
                if (!updating_position) player.seek (value);
                return false;
            });
            middle.append (position_scale);
            clock = text_label ("0:00 / 0:00");
            clock.halign = Gtk.Align.CENTER;
            middle.append (clock);
            bar.append (middle);
            var volume = new Gtk.Scale.with_range (Gtk.Orientation.HORIZONTAL, 0, 1, 0.01);
            volume.width_request = 120;
            volume.draw_value = false;
            volume.tooltip_text = "Volumen";
            volume.set_value (player.volume);
            volume.value_changed.connect (() => { player.volume = volume.get_value (); });
            bar.append (new Gtk.Image.from_icon_name ("audio-volume-high-symbolic"));
            bar.append (volume);
            return bar;
        }

        private async void choose_folder () {
            var dialog = new Gtk.FileDialog ();
            dialog.title = "Elegir ubicación de música";
            try {
                var folder = yield dialog.select_folder (this, null);
                location.text = folder.get_uri ();
            } catch (Error e) { /* Dismissing the chooser is not a load error. */ }
        }

        public async void load_library (string input) {
            if (loading || closed) return;
            loading = true;
            load_button.sensitive = location.sensitive = false;
            cancel_button.sensitive = true;
            spinner.start ();
            status.label = "Leyendo biblioteca… (se mostrará al terminar)";
            scan_cancel = new Cancellable ();
            try {
                var folder = LocationSettings.parse_location (input);
                var scanner = new Scanner ();
                Track[] loaded;
                try {
                    loaded = yield scanner.scan (folder, scan_cancel);
                } catch (IOError.NOT_MOUNTED e) {
                    status.label = "Conectando con la ubicación…";
                    var operation = new Gtk.MountOperation (this);
                    operation.password_save = PasswordSave.NEVER;
                    operation.reply.connect ((result) => { operation.password_save = PasswordSave.NEVER; });
                    try { yield folder.mount_enclosing_volume (MountMountFlags.NONE, operation, scan_cancel); }
                    catch (IOError.ALREADY_MOUNTED e) { }
                    loaded = yield scanner.scan (folder, scan_cancel);
                }
                if (closed) return;
                scan_cancel.set_error_if_cancelled ();
                // Keep album track order stable rather than the server's enumeration order.
                var ordered = new List<Track> ();
                foreach (var track in loaded) ordered.append (track);
                ordered.sort ((a, b) => {
                    int order = a.artist.collate (b.artist);
                    if (order == 0) order = a.album.collate (b.album);
                    if (order == 0) order = (int) a.number - (int) b.number;
                    return order == 0 ? a.title.collate (b.title) : order;
                });
                library = {};
                foreach (var track in ordered) library += track;
                rebuild_groups ();
                location.text = folder.get_uri ();
                status.label = "%u pistas cargadas · %u archivos de audio omitidos".printf (library.length, scanner.skipped);
                try { new LocationSettings (config_path).save (folder.get_uri ()); }
                catch (Error e) { status.label += " · No se pudo recordar la ubicación: " + e.message; }
            } catch (IOError.CANCELLED e) {
                if (!closed) status.label = "Carga cancelada. Se conserva la biblioteca anterior.";
            } catch (Error e) {
                if (!closed) status.label = "No se pudo cargar la ubicación: " + e.message;
            } finally {
                loading = false;
                scan_cancel = null;
                if (!closed) {
                    load_button.sensitive = location.sensitive = true;
                    cancel_button.sensitive = false;
                    spinner.stop ();
                }
            }
        }

        private string group_key (Track track) {
            return grouping.selected == 1 ? track.artist : track.album + " — " + track.artist;
        }
        private void rebuild_groups () {
            clear_list (groups);
            group_keys = {};
            groups.append (text_label ("Todas las pistas"));
            var seen = new HashTable<string, bool> (str_hash, str_equal);
            foreach (var track in library) {
                string key = group_key (track);
                if (seen.contains (key)) continue;
                seen.insert (key, true);
                group_keys += key;
                groups.append (text_label (key));
            }
            groups.select_row (groups.get_row_at_index (0));
        }
        private void show_tracks (Track[] selection, string title) {
            visible_tracks = selection;
            clear_list (tracks);
            heading.label = title + " · %u pistas".printf (selection.length);
            foreach (var track in selection) {
                var row = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 12);
                row.margin_start = row.margin_end = 12;
                row.margin_top = row.margin_bottom = 10;
                var label = text_label (track.title + "\n" + track.artist);
                label.hexpand = true;
                label.ellipsize = Pango.EllipsizeMode.END;
                row.append (label);
                row.append (text_label (time_text ((double) track.duration / Gst.SECOND)));
                tracks.append (row);
            }
        }
        private void refresh_queue () {
            clear_list (queue_list);
            foreach (var track in queue.tracks) queue_list.append (text_label (track.title + "\n" + track.artist));
            queue_list.select_row (queue_list.get_row_at_index (queue.index));
        }
        private void update_player () {
            play_button.icon_name = player.state == Gst.State.PLAYING ? "media-playback-pause-symbolic" : "media-playback-start-symbolic";
            var track = queue.current;
            if (track == null) return;
            now_playing.label = track.title + "\n" + track.artist;
            info.label = track.title + "\n\nArtista: " + track.artist + "\nÁlbum: " + track.album +
                "\nPista: " + (track.number == 0 ? "Sin número" : track.number.to_string ()) +
                "\nDuración: " + time_text ((double) track.duration / Gst.SECOND) + "\n\n" + track.uri;
            queue_list.select_row (queue_list.get_row_at_index (queue.index));
        }
        private static void clear_list (Gtk.ListBox list) {
            while (list.get_first_child () != null) list.remove (list.get_first_child ());
        }
        private static Gtk.Label text_label (string text) {
            var label = new Gtk.Label (text);
            label.xalign = 0;
            return label;
        }
        private static Gtk.Label title_label (string text) {
            var label = text_label (text);
            label.add_css_class ("heading");
            return label;
        }
        private static Gtk.ScrolledWindow scroll (Gtk.Widget child) {
            var scroll = new Gtk.ScrolledWindow ();
            scroll.hscrollbar_policy = Gtk.PolicyType.NEVER;
            scroll.vexpand = true;
            scroll.child = child;
            return scroll;
        }
        private static Gtk.Button icon_button (string icon, string tooltip) {
            var button = new Gtk.Button.from_icon_name (icon);
            button.tooltip_text = tooltip;
            return button;
        }
        private static string time_text (double seconds) {
            int total = (int) seconds;
            return "%d:%02d".printf (total / 60, total % 60);
        }
    }
}
