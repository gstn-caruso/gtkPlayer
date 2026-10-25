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
        private Adw.PreferencesWindow preferences;
        private Gtk.Label preference_status;
        private Gtk.Entry location;
        private Gtk.Button load_button;
        private Gtk.Button reload_button;
        private Gtk.Button browse_button;
        private Gtk.Button cancel_button;
        private Gtk.Button play_button;
        private Gtk.Button previous_button;
        private Gtk.Button next_button;
        private Gtk.Spinner spinner;
        private Adw.ToastOverlay notices;
        private Adw.Toast? error_toast;
        private Gtk.Label heading;
        private Gtk.Label selection_hint;
        private Adw.StatusPage queue_empty;
        private Gtk.Label info;
        private Gtk.Label now_playing;
        private Gtk.Label elapsed_time;
        private Gtk.Label duration_time;
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
            player.failure.connect ((message) => {
                if (closed) return;
                show_error ("No se pudo reproducir. Revisá Preferencias.", message);
            });
            player.finished.connect (() => {
                if (!closed) preference_status.label = "Fin de la cola";
            });
            ticker = Timeout.add (500, () => {
                double duration = player.duration ();
                updating_position = true;
                position_scale.set_range (0, duration > 0 ? duration : 1);
                position_scale.set_value (player.position ());
                position_scale.sensitive = duration > 0;
                updating_position = false;
                elapsed_time.label = time_text (player.position ());
                duration_time.label = time_text (duration);
                return Source.CONTINUE;
            });
            close_request.connect (() => {
                closed = true;
                preferences.set_focus (null);
                preferences.destroy ();
                if (scan_cancel != null) scan_cancel.cancel ();
                player.shutdown ();
                if (ticker != 0) { Source.remove (ticker); ticker = 0; }
                return false;
            });
            load_library.begin (new LocationSettings (config_path).load ());
        }

        private void build_ui () {
            var root = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            var header = new Adw.HeaderBar ();
            header.title_widget = new Gtk.Label ("Tu música, en tu red");
            root.append (header);
            build_preferences ();
            var settings_button = icon_button ("emblem-system-symbolic", "Preferencias");
            settings_button.name = "open-preferences";
            settings_button.clicked.connect (() => {
                location.text = new LocationSettings (config_path).load ();
                preferences.present ();
            });
            header.pack_end (settings_button);
            spinner = new Gtk.Spinner ();
            header.pack_end (spinner);

            var left = new Gtk.Box (Gtk.Orientation.VERTICAL, 10);
            left.name = "library";
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
            heading = title_label ("Leyendo biblioteca…");
            heading.add_css_class ("title-1");
            summary_text.append (heading);
            selection_hint = text_label ("La música aparecerá aquí al terminar la carga");
            selection_hint.wrap = true;
            summary_text.append (selection_hint);
            summary.append (summary_text);
            center.append (summary);
            tracks = new Gtk.ListBox ();
            tracks.add_css_class ("boxed-list");
            tracks.activate_on_single_click = true;
            tracks.row_activated.connect ((row) => {
                queue.replace (visible_tracks);
                if (queue.select (row.get_index ())) { player.stop (); player.play (); refresh_queue (); }
            });
            center.append (scroll (tracks));

            var right = new Gtk.Box (Gtk.Orientation.VERTICAL, 10);
            right.name = "details";
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
            queue_empty = new Adw.StatusPage ();
            queue_empty.name = "queue-empty";
            queue_empty.icon_name = "view-list-symbolic";
            queue_empty.title = "Cola vacía";
            queue_empty.description = "Cargá música desde Preferencias y activá una pista para crear la cola";
            queue_list.set_placeholder (queue_empty);
            queue_list.activate_on_single_click = true;
            queue_list.row_activated.connect ((row) => {
                if (queue.select (row.get_index ())) { player.stop (); player.play (); }
            });
            stack.add_titled (scroll (queue_list), "queue", "Cola");
            right.append (stack);
            var inner = new Gtk.Paned (Gtk.Orientation.HORIZONTAL);
            inner.start_child = panel_viewport (center);
            inner.end_child = panel_viewport (right);
            inner.position = 710;
            inner.wide_handle = true;
            inner.resize_end_child = false;
            inner.shrink_start_child = inner.shrink_end_child = true;
            var panels = new Gtk.Paned (Gtk.Orientation.HORIZONTAL);
            panels.start_child = panel_viewport (left);
            panels.end_child = inner;
            panels.position = 258;
            panels.wide_handle = true;
            panels.resize_start_child = false;
            panels.shrink_start_child = true;
            panels.vexpand = true;
            notices = new Adw.ToastOverlay ();
            notices.name = "library-notices";
            notices.child = panels;
            notices.vexpand = true;
            root.append (notices);
            root.append (new Gtk.Separator (Gtk.Orientation.HORIZONTAL));
            root.append (build_controls ());
            content = root;
            update_player ();
        }

        private Gtk.Widget build_controls () {
            var bar = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 12);
            bar.name = "controls";
            bar.margin_start = bar.margin_end = 12;
            bar.margin_top = bar.margin_bottom = 6;
            var current = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 12);
            current.width_request = 240;
            var artwork = new Gtk.Image.from_icon_name ("audio-x-generic-symbolic");
            artwork.pixel_size = 48;
            current.append (artwork);
            now_playing = text_label ("Nada en reproducción");
            now_playing.name = "now-playing";
            now_playing.hexpand = true;
            now_playing.ellipsize = Pango.EllipsizeMode.END;
            current.append (now_playing);
            bar.append (current);
            var middle = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            middle.hexpand = true;
            var buttons = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
            buttons.add_css_class ("toolbar");
            buttons.halign = Gtk.Align.CENTER;
            previous_button = icon_button ("media-skip-backward-symbolic", "Anterior");
            previous_button.clicked.connect (() => { player.previous (); });
            buttons.append (previous_button);
            play_button = icon_button ("media-playback-start-symbolic", "Reproducir o pausar");
            play_button.add_css_class ("circular");
            play_button.add_css_class ("raised");
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
            next_button = icon_button ("media-skip-forward-symbolic", "Siguiente");
            next_button.clicked.connect (() => { player.next (); });
            buttons.append (next_button);
            middle.append (buttons);
            var progress = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
            elapsed_time = text_label ("0:00");
            elapsed_time.name = "elapsed";
            elapsed_time.add_css_class ("numeric");
            elapsed_time.add_css_class ("dim-label");
            progress.append (elapsed_time);
            position_scale = new Gtk.Scale.with_range (Gtk.Orientation.HORIZONTAL, 0, 1, 1);
            position_scale.name = "position";
            position_scale.tooltip_text = "Posición de reproducción";
            position_scale.hexpand = true;
            position_scale.draw_value = false;
            position_scale.sensitive = false;
            position_scale.change_value.connect ((type, value) => {
                if (!updating_position) player.seek (value);
                return false;
            });
            progress.append (position_scale);
            duration_time = text_label ("0:00");
            duration_time.name = "duration";
            duration_time.add_css_class ("numeric");
            duration_time.add_css_class ("dim-label");
            progress.append (duration_time);
            middle.append (progress);
            bar.append (middle);
            var volume_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
            volume_box.halign = Gtk.Align.FILL;
            var side_sizes = new Gtk.SizeGroup (Gtk.SizeGroupMode.HORIZONTAL);
            side_sizes.add_widget (current);
            side_sizes.add_widget (volume_box);
            var volume = new Gtk.Scale.with_range (Gtk.Orientation.HORIZONTAL, 0, 1, 0.01);
            volume.name = "volume";
            volume.width_request = 120;
            volume.halign = Gtk.Align.END;
            volume.draw_value = false;
            volume.tooltip_text = "Volumen";
            volume.set_value (player.volume);
            volume.value_changed.connect (() => { player.volume = volume.get_value (); });
            var volume_spacer = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
            volume_spacer.hexpand = true;
            volume_box.append (volume_spacer);
            volume_box.append (new Gtk.Image.from_icon_name ("audio-volume-high-symbolic"));
            volume_box.append (volume);
            bar.append (volume_box);
            return bar;
        }

        private void build_preferences () {
            preferences = new Adw.PreferencesWindow ();
            preferences.title = "Preferencias";
            preferences.transient_for = this;
            preferences.modal = true;
            preferences.hide_on_close = true;
            preferences.close_request.connect (() => {
                preferences.set_focus (null);
                return false;
            });
            preferences.destroy_with_parent = true;
            preferences.default_width = 620;
            var page = new Adw.PreferencesPage ();
            var group = new Adw.PreferencesGroup ();
            group.title = "Biblioteca musical";
            var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 12);
            location = new Gtk.Entry ();
            location.name = "location";
            location.placeholder_text = "Carpeta local, file:// o smb://";
            location.text = new LocationSettings (config_path).load ();
            box.append (location);
            var buttons = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
            browse_button = new Gtk.Button.with_label ("Elegir carpeta…");
            browse_button.name = "browse";
            browse_button.clicked.connect (() => { choose_folder.begin (); });
            box.append (browse_button);
            load_button = new Gtk.Button.with_label ("Aplicar y cargar");
            load_button.name = "apply";
            load_button.add_css_class ("suggested-action");
            load_button.clicked.connect (apply_location);
            location.activate.connect (apply_location);
            buttons.append (load_button);
            reload_button = new Gtk.Button.with_label ("Recargar");
            reload_button.name = "reload";
            reload_button.clicked.connect (() => { load_library.begin (new LocationSettings (config_path).load ()); });
            buttons.append (reload_button);
            cancel_button = new Gtk.Button.with_label ("Cancelar escaneo");
            cancel_button.name = "cancel";
            cancel_button.sensitive = false;
            cancel_button.clicked.connect (() => { if (scan_cancel != null) scan_cancel.cancel (); });
            buttons.append (cancel_button);
            box.append (buttons);
            preference_status = text_label ("");
            preference_status.name = "preferences-status";
            preference_status.wrap = true;
            preference_status.selectable = true;
            box.append (preference_status);
            group.add (box);
            page.add (group);
            preferences.add (page);
        }

        private void show_error (string message, string detail) {
            if (closed) return;
            preference_status.label = detail;
            if (error_toast != null) error_toast.dismiss ();
            var toast = new Adw.Toast (message);
            toast.timeout = 3;
            toast.use_markup = false;
            error_toast = toast;
            notices.add_toast (toast);
        }

        private void apply_location () {
            if (loading || closed) return;
            try {
                var folder = LocationSettings.parse_location (location.text);
                new LocationSettings (config_path).save (folder.get_uri ());
                location.text = folder.get_uri ();
                load_library.begin (folder.get_uri ());
            } catch (Error e) {
                show_error ("No se pudo guardar la ubicación. Revisá Preferencias.", e.message);
            }
        }

        private async void choose_folder () {
            var dialog = new Gtk.FileDialog ();
            dialog.title = "Elegir ubicación de música";
            try {
                var folder = yield dialog.select_folder (preferences, null);
                if (!closed) location.text = folder.get_uri ();
            } catch (Error e) { /* Dismissing the chooser is not a load error. */ }
        }

        public async void load_library (string input) {
            if (loading || closed) return;
            loading = true;
            cancel_button.sensitive = true;
            if (preferences.visible) cancel_button.grab_focus ();
            load_button.sensitive = location.sensitive = reload_button.sensitive = browse_button.sensitive = false;
            spinner.start ();
            preference_status.label = "Leyendo biblioteca…";
            scan_cancel = new Cancellable ();
            try {
                var folder = LocationSettings.parse_location (input);
                var scanner = new Scanner ();
                Track[] loaded;
                try {
                    loaded = yield scanner.scan (folder, scan_cancel);
                } catch (IOError.NOT_MOUNTED e) {
                    if (closed) return;
                    preference_status.label = "Conectando con la ubicación…";
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
                preference_status.label = (library.length == 1 ? "%u pista cargada" : "%u pistas cargadas").printf (library.length) +
                    " · " + (scanner.skipped == 1 ? "%u archivo de audio omitido" : "%u archivos de audio omitidos").printf (scanner.skipped);
            } catch (IOError.CANCELLED e) {
                if (!closed) {
                    preference_status.label = "Carga cancelada. Se conserva la biblioteca anterior.";
                }
            } catch (Error e) {
                if (!closed) {
                    if (library.length == 0) {
                        heading.label = "No se pudo cargar la biblioteca";
                        selection_hint.label = "Revisá la ubicación en Preferencias y volvé a cargar";
                    }
                    show_error ("No se pudo cargar la biblioteca. Revisá Preferencias.", e.message);
                }
            } finally {
                loading = false;
                scan_cancel = null;
                if (!closed) {
                    load_button.sensitive = location.sensitive = reload_button.sensitive = browse_button.sensitive = true;
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
            heading.label = selection.length == 0 ? "Biblioteca vacía" :
                title + (selection.length == 1 ? " · %u pista" : " · %u pistas").printf (selection.length);
            selection_hint.label = selection.length == 0 ? "Elegí una ubicación con música en Preferencias" :
                "Activá una pista para reproducir la selección";
            queue_empty.description = library.length == 0 ?
                "Cargá música desde Preferencias y activá una pista para crear la cola" :
                "Activá una pista para reproducir la selección y crear la cola";
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
            update_player ();
        }
        private void refresh_queue () {
            clear_list (queue_list);
            foreach (var track in queue.tracks) queue_list.append (text_label (track.title + "\n" + track.artist));
            queue_list.select_row (queue_list.get_row_at_index (queue.index));
        }
        private void update_player () {
            if (closed) return;
            play_button.icon_name = player.state == Gst.State.PLAYING ? "media-playback-pause-symbolic" : "media-playback-start-symbolic";
            var track = queue.current;
            play_button.sensitive = track != null || visible_tracks.length > 0;
            previous_button.sensitive = track != null && queue.index > 0;
            next_button.sensitive = track != null && queue.index + 1 < queue.tracks.length;
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
        private static Gtk.ScrolledWindow panel_viewport (Gtk.Widget child) {
            // Keep controls at a safe minimum internally, but clip them instead of
            // imposing that minimum on the draggable panel or its neighbours.
            var viewport = new Gtk.ScrolledWindow ();
            viewport.hscrollbar_policy = Gtk.PolicyType.EXTERNAL;
            viewport.vscrollbar_policy = Gtk.PolicyType.NEVER;
            viewport.child = child;
            return viewport;
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
