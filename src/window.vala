namespace Music {
    public class Window : Adw.ApplicationWindow {
        public signal void library_updated ();
        public uint track_count { get { return library.length; } }
        public bool loading { get; private set; default = false; }
        private string config_path;
        private LibraryCache cache;
        private string? library_uri;
        private Track[] library = {};
        private Track[] visible_tracks = {};
        private string browsing_page = "albums";
        private string? selected_artist;
        private string? selected_album;
        private Gtk.SearchEntry search;
        private Gtk.Stack browser_stack;
        private Gtk.Button library_back;
        private ListStore album_store;
        private ListStore artist_store;
        private ListStore track_store;
        private ListStore queue_store;
        private Gtk.SingleSelection track_selection;
        private Gtk.SingleSelection queue_selection;
        private Gtk.Label queue_count;
        private Gtk.Button clear_button;
        private Gtk.Button undo_button;
        private Gtk.Image now_cover;
        private string? now_cover_uri;
        private Gtk.CheckButton stop_after;
        private Cancellable? import_cancel;
        private Gtk.Box import_activity;
        private Gtk.Label import_status;
        private Gtk.Spinner import_spinner;
        private MediaRow? drop_row;
        private Gtk.Overlay queue_drop_area;
        private uint drop_scroll;
        private double drop_x;
        private double drop_y;
        private Adw.OverlaySplitView navigation_overlay;
        private Adw.OverlaySplitView details_overlay;
        private bool compact;
        private PlayQueue queue = new PlayQueue ();
        private Player player;
        private SessionStore session;
        private bool session_ready;
        private uint session_ticks;
        private Cancellable? scan_cancel;
        private HashTable<string, FileMonitor> directory_monitors = new HashTable<string, FileMonitor> (str_hash, str_equal);
        private string? watched_uri;
        private uint refresh_timer;
        private uint fallback_timer;
        private bool refresh_pending;
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
        private Gtk.Button stop_button;
        private Gtk.MenuButton playback_options;
        private string? displayed_current;
        private Bytes? now_cover_data;
        private string empty_title = "Leyendo biblioteca…";
        private string empty_hint = "La música aparecerá aquí al terminar la carga";
        private Gtk.Spinner spinner;
        private Adw.ToastOverlay notices;
        private Adw.Toast? error_toast;
        private Gtk.Image cover;
        private Gtk.Label heading;
        private Gtk.Label selection_hint;
        private Adw.StatusPage queue_empty;
        private Gtk.Label info;
        private ArtistPhotos? photos;
        private Cancellable? photo_cancel;
        private string? portrait_artist;
        private HashTable<string, ArtistPhoto> photo_cache = new HashTable<string, ArtistPhoto> (str_hash, str_equal);
        private Gtk.Box artist_card;
        private Gtk.Image artist_portrait;
        private Gtk.Label artist_name;
        private Gtk.Label photo_author;
        private Gtk.Label photo_status;
        private Gtk.LinkButton photo_license;
        private Gtk.LinkButton photo_source;
        private Gtk.Label now_playing;
        private Gtk.Label elapsed_time;
        private Gtk.Label duration_time;
        private Gtk.ListBox groups;
        private Gtk.ListView tracks;
        private Gtk.ListView queue_list;
        private Gtk.Scale position_scale;
        private uint ticker;
        private bool updating_position;
        private bool closed;
        private Gtk.CssProvider insertion_style = new Gtk.CssProvider ();
        private Gtk.CssProvider album_style = new Gtk.CssProvider ();
        private Gdk.RGBA? album_color;
        private Adw.StyleManager theme;
        private ulong dark_changed;
        private ulong contrast_changed;

        public Window (Gtk.Application app, string config_path, Gst.Element? sink = null, ArtistPhotos? photos = null, string? cache_path = null) {
            Object (application: app, title: "Música · GTK Player", default_width: 1280, default_height: 800);
            this.config_path = config_path;
            cache = new LibraryCache (cache_path ?? Path.build_filename (Environment.get_user_cache_dir (), "gtkplayer"));
            this.photos = photos;
            player = new Player (queue, sink);
            session = new SessionStore (Path.build_filename (Path.get_dirname (config_path), "session.ini"));
            build_ui ();
            theme = Adw.StyleManager.get_for_display (get_display ());
            weak Window window = this;
            dark_changed = theme.notify["dark"].connect (() => {
                if (window != null) window.update_album_style ();
            });
            contrast_changed = theme.notify["high-contrast"].connect (() => {
                if (window != null) window.update_album_style ();
            });
            player.changed.connect (() => { update_player (); save_session (); });
            queue.changed.connect (() => {
                if (closed) return;
                refresh_queue ();
                update_player ();
                save_session ();
            });
            session.failure.connect ((message) => { if (!closed) show_error ("No se pudo guardar la cola. Revisá Preferencias.", message); });
            player.failure.connect ((message) => {
                if (closed) return;
                show_error ("No se pudo reproducir. Revisá Preferencias.", message);
            });
            player.finished.connect (() => {
                if (!closed) preference_status.label = queue.index + 1 < queue.entries.length ? "Detenido al terminar la canción" : "Fin de la cola";
            });
            ticker = Timeout.add (500, () => {
                double duration = player.duration ();
                if (duration <= 0 && queue.current != null) duration = (double) queue.current.duration / Gst.SECOND;
                double position = player.saved_position;
                updating_position = true;
                position_scale.set_range (0, duration > 0 ? duration : 1);
                position_scale.set_value (position);
                position_scale.sensitive = duration > 0 && player.state >= Gst.State.PAUSED;
                updating_position = false;
                elapsed_time.label = time_text (position);
                duration_time.label = time_text (duration);
                if (++session_ticks >= 20) { session_ticks = 0; save_session (); }
                return Source.CONTINUE;
            });
            close_request.connect (() => {
                if (!session_ready && queue.revision > 0)
                    session.save (new QueueSession.capture (queue, player.saved_position));
                save_session ();
                var owner = application;
                owner.hold ();
                session.flush.begin (() => { owner.release (); });
                closed = true;
                stop_watching ();
                theme.disconnect (dark_changed);
                theme.disconnect (contrast_changed);
                album_style.load_from_data ("".data);
                Gtk.StyleContext.remove_provider_for_display (get_display (), insertion_style);
                preferences.set_focus (null);
                preferences.destroy ();
                if (scan_cancel != null) scan_cancel.cancel ();
                if (photo_cancel != null) photo_cancel.cancel ();
                if (import_cancel != null) import_cancel.cancel ();
                if (drop_scroll != 0) { Source.remove (drop_scroll); drop_scroll = 0; }
                photo_cancel = null;
                player.shutdown ();
                if (ticker != 0) { Source.remove (ticker); ticker = 0; }
                return false;
            });
            restore_session.begin ();
            load_library.begin (new LocationSettings (config_path).load (), true);
        }

        private async void restore_session () {
            uint revision = queue.revision;
            var saved = yield session.load ();
            if (closed) return;
            if (revision == queue.revision && queue.current == null) {
                queue.restore (saved.entries, saved.current_id);
                player.restore_position (saved.position);
                reconcile_queue_artwork ();
            }
            session_ready = true;
        }
        public async void flush_session () {
            yield session.flush ();
        }
        private void save_session () {
            if (session_ready && !closed) session.save (new QueueSession.capture (queue, player.saved_position));
        }

        private void build_ui () {
            var root = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            root.add_css_class ("album-backdrop");
            root.get_style_context ().add_provider (album_style, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION);
            var header = new Adw.HeaderBar ();
            header.get_style_context ().add_provider (album_style, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION);
            header.title_widget = new Gtk.Label ("Tu biblioteca");
            root.append (header);
            insertion_style.load_from_data (".queue-insertion { min-height: 3px; background-color: @accent_color; }".data);
            Gtk.StyleContext.add_provider_for_display (get_display (), insertion_style, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION);
            build_preferences ();
            var settings_button = icon_button ("emblem-system-symbolic", "Preferencias");
            settings_button.name = "open-preferences";
            settings_button.clicked.connect (() => {
                location.text = new LocationSettings (config_path).load ();
                preferences.present ();
            });
            header.pack_end (settings_button);
            library_back = icon_button ("go-previous-symbolic", "Volver a la biblioteca");
            library_back.name = "library-back";
            library_back.visible = false;
            library_back.clicked.connect (go_back_in_library);
            header.pack_start (library_back);
            spinner = new Gtk.Spinner ();
            header.pack_end (spinner);

            var left = new Gtk.Box (Gtk.Orientation.VERTICAL, 10);
            left.name = "library";
            left.margin_start = left.margin_end = 12;
            left.append (title_label ("Tu biblioteca"));
            groups = new Gtk.ListBox ();
            groups.add_css_class ("navigation-sidebar");
            foreach (string label in new string[] {"Álbumes", "Artistas", "Canciones"}) groups.append (text_label (label));
            groups.select_row (groups.get_row_at_index (0));
            groups.activate_on_single_click = true;
            groups.row_selected.connect ((row) => { if (row != null) navigate_library (row.get_index ()); });
            groups.row_activated.connect ((row) => { navigate_library (row.get_index ()); });
            left.append (scroll (groups));

            var center = new Gtk.Box (Gtk.Orientation.VERTICAL, 12);
            center.name = "tracks";
            center.hexpand = true;
            center.margin_start = center.margin_end = 20;
            var summary = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 20);
            summary.margin_top = summary.margin_bottom = 20;
            cover = new Gtk.Image.from_icon_name ("audio-x-generic-symbolic");
            cover.pixel_size = 96;
            cover.valign = Gtk.Align.CENTER;
            summary.append (cover);
            var summary_text = new Gtk.Box (Gtk.Orientation.VERTICAL, 8);
            summary_text.valign = Gtk.Align.CENTER;
            heading = title_label ("Leyendo biblioteca…");
            heading.add_css_class ("title-1");
            heading.ellipsize = Pango.EllipsizeMode.END;
            heading.max_width_chars = 30;
            heading.tooltip_text = heading.label;
            summary_text.append (heading);
            selection_hint = text_label ("La música aparecerá aquí al terminar la carga");
            selection_hint.wrap = true;
            summary_text.append (selection_hint);
            summary.append (summary_text);
            var selection_menu = new Gtk.MenuButton ();
            selection_menu.label = "Acciones de la selección";
            selection_menu.halign = Gtk.Align.START;
            var selection_popover = new Gtk.Popover ();
            var selection_actions = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            foreach (string action in new string[] {"append", "next", "now"}) {
                string selected_action = action;
                var button = new Gtk.Button.with_label (action == "append" ? "Agregar a la cola" : action == "next" ? "Reproducir a continuación" : "Reproducir ahora");
                button.clicked.connect (() => { music_action (visible_tracks, selected_action); });
                selection_actions.append (button);
            }
            selection_popover.child = selection_actions;
            selection_menu.popover = selection_popover;
            summary_text.append (selection_menu);
            center.append (summary);
            search = new Gtk.SearchEntry ();
            search.name = "library-search";
            search.placeholder_text = "Buscar título, artista o álbum";
            search.search_changed.connect (() => { rebuild_groups (); });
            center.append (search);
            browser_stack = new Gtk.Stack ();
            browser_stack.vexpand = true;
            track_store = new ListStore (typeof (Track));
            track_selection = new Gtk.SingleSelection (track_store);
            tracks = new Gtk.ListView (track_selection, media_factory ("track"));
            tracks.name = "song-list";
            tracks.add_css_class ("boxed-list");
            tracks.single_click_activate = true;
            tracks.activate.connect ((index) => {
                var track = track_store.get_item (index) as Track;
                if (track != null) music_action ({track}, "now");
            });
            browser_stack.add_named (scroll (tracks), "songs");
            album_store = new ListStore (typeof (LibraryGroup));
            var album_selection = new Gtk.SingleSelection (album_store);
            var albums = new Gtk.GridView (album_selection, media_factory ("album"));
            albums.name = "album-grid";
            albums.min_columns = 1;
            albums.max_columns = 8;
            albums.single_click_activate = true;
            albums.activate.connect ((index) => { open_album ((LibraryGroup) album_store.get_item (index)); });
            browser_stack.add_named (scroll (albums), "albums");
            artist_store = new ListStore (typeof (LibraryGroup));
            var artists = new Gtk.ListView (new Gtk.SingleSelection (artist_store), media_factory ("artist"));
            artists.name = "artist-list";
            artists.single_click_activate = true;
            artists.activate.connect ((index) => { open_artist ((LibraryGroup) artist_store.get_item (index)); });
            browser_stack.add_named (scroll (artists), "artists");
            center.append (browser_stack);

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
            info.wrap_mode = Pango.WrapMode.WORD_CHAR;
            info.selectable = true;
            var data = new Gtk.Box (Gtk.Orientation.VERTICAL, 16);
            data.append (build_artist_card ());
            data.append (new Gtk.Separator (Gtk.Orientation.HORIZONTAL));
            data.append (info);
            var data_scroll = scroll (data);
            queue_store = new ListStore (typeof (QueueEntry));
            queue_selection = new Gtk.SingleSelection (queue_store);
            queue_list = new Gtk.ListView (queue_selection, media_factory ("queue"));
            queue_list.name = "queue-list";
            queue_empty = new Adw.StatusPage ();
            queue_empty.name = "queue-empty";
            queue_empty.add_css_class ("compact");
            queue_empty.icon_name = "view-list-symbolic";
            queue_empty.title = "Cola vacía";
            queue_empty.description = "Agregá música desde la biblioteca o archivos y carpetas";
            queue_list.single_click_activate = true;
            queue_list.activate.connect ((index) => { player.activate ((int) index); });
            var queue_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 6);
            var queue_toolbar = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
            queue_count = text_label ("0 pistas");
            queue_count.name = "queue-count";
            queue_count.hexpand = true;
            queue_toolbar.append (queue_count);
            clear_button = icon_button ("edit-clear-all-symbolic", "Vaciar cola");
            clear_button.name = "clear-queue";
            clear_button.clicked.connect (clear_queue);
            queue_toolbar.append (clear_button);
            undo_button = icon_button ("edit-undo-symbolic", "Deshacer vaciado");
            undo_button.name = "undo-queue";
            undo_button.clicked.connect (() => { queue.undo_clear (); });
            queue_toolbar.append (undo_button);
            queue_box.append (queue_toolbar);
            var import_buttons = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
            var add_files = icon_button ("list-add-symbolic", "Agregar archivos a la cola…");
            add_files.clicked.connect (() => { choose_import.begin (false); });
            import_buttons.append (add_files);
            var add_folder = icon_button ("folder-open-symbolic", "Agregar carpetas a la cola…");
            add_folder.clicked.connect (() => { choose_import.begin (true); });
            import_buttons.append (add_folder);
            queue_box.append (import_buttons);
            import_activity = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
            import_spinner = new Gtk.Spinner ();
            import_activity.append (import_spinner);
            import_status = text_label ("");
            import_status.wrap = true;
            import_status.hexpand = true;
            import_activity.append (import_status);
            var cancel_import = icon_button ("process-stop-symbolic", "Cancelar importación");
            cancel_import.name = "cancel-import";
            cancel_import.clicked.connect (() => { if (import_cancel != null) import_cancel.cancel (); });
            import_activity.append (cancel_import);
            import_activity.visible = false;
            queue_box.append (import_activity);
            var queue_scroll = scroll (queue_list);

            // The empty placeholder also accepts drops: the list remains allocated behind it.
            var queue_overlay = new Gtk.Overlay ();
            queue_drop_area = queue_overlay;
            queue_overlay.name = "queue-drop-area";
            queue_overlay.child = queue_scroll;
            queue_empty.can_target = false;
            queue_overlay.add_overlay (queue_empty);
            queue_overlay.vexpand = true;
            queue_box.append (queue_overlay);
            install_queue_drop (queue_scroll);
            // Empty-space drops land on the list's full viewport.
            queue_list.vexpand = true;
            stack.add_titled (queue_box, "queue", "Cola");
            stack.add_titled (data_scroll, "data", "Datos");
            stack.visible_child_name = "queue";
            right.append (stack);
            var inner = new Gtk.Paned (Gtk.Orientation.HORIZONTAL);
            inner.start_child = panel_viewport (center);
            var right_viewport = panel_viewport (right);
            inner.end_child = right_viewport;
            inner.position = 710;
            inner.wide_handle = true;
            inner.resize_end_child = false;
            inner.shrink_start_child = inner.shrink_end_child = true;
            var panels = new Gtk.Paned (Gtk.Orientation.HORIZONTAL);
            var left_viewport = panel_viewport (left);
            panels.start_child = left_viewport;
            panels.end_child = inner;
            double library_proportion = 258.0 / 1280.0;
            int panel_width = 0;
            bool updating_panel_position = false;
            panels.notify["position"].connect (() => {
                if (!compact && !updating_panel_position && panel_width > 0 && panels.get_width () == panel_width)
                    library_proportion = (double) panels.position / panel_width;
            });
            panels.add_tick_callback ((widget, clock) => {
                int width = widget.get_width ();
                if (!compact && width > 0 && width != panel_width) {
                    updating_panel_position = true;
                    panels.position = (int) (library_proportion * width + 0.5);
                    panel_width = width;
                    updating_panel_position = false;
                }
                return Source.CONTINUE;
            });
            panels.wide_handle = true;
            panels.resize_start_child = false;
            panels.shrink_start_child = true;
            panels.vexpand = true;
            notices = new Adw.ToastOverlay ();
            notices.name = "library-notices";
            details_overlay = new Adw.OverlaySplitView ();
            details_overlay.collapsed = true;
            details_overlay.show_sidebar = false;
            details_overlay.sidebar_position = Gtk.PackType.END;
            details_overlay.min_sidebar_width = 320;
            details_overlay.max_sidebar_width = 400;
            details_overlay.content = panels;
            navigation_overlay = new Adw.OverlaySplitView ();
            navigation_overlay.collapsed = true;
            navigation_overlay.show_sidebar = false;
            navigation_overlay.content = details_overlay;
            var library_toggle = icon_button ("sidebar-show-symbolic", "Mostrar biblioteca");
            library_toggle.name = "show-library";
            library_toggle.clicked.connect (() => { navigation_overlay.show_sidebar = !navigation_overlay.show_sidebar; });
            header.pack_start (library_toggle);
            var queue_toggle = icon_button ("view-list-symbolic", "Mostrar cola y datos");
            queue_toggle.name = "show-details";
            queue_toggle.clicked.connect (() => { details_overlay.show_sidebar = !details_overlay.show_sidebar; });
            header.pack_end (queue_toggle);
            double detail_proportion = 0.64;
            int inner_width = 0;
            bool updating_inner = false;
            inner.notify["position"].connect (() => {
                if (!compact && !updating_inner && inner_width > 0 && inner.get_width () == inner_width)
                    detail_proportion = (double) inner.position / inner_width;
            });
            root.add_tick_callback ((widget, clock) => {
                bool narrow = widget.get_width () < 1100;
                library_toggle.visible = queue_toggle.visible = narrow;
                if (narrow != compact) {
                    compact = narrow;
                    if (narrow) {
                        panels.start_child = null;
                        inner.end_child = null;
                        navigation_overlay.sidebar = left_viewport;
                        details_overlay.sidebar = right_viewport;
                    } else {
                        navigation_overlay.show_sidebar = details_overlay.show_sidebar = false;
                        navigation_overlay.sidebar = details_overlay.sidebar = null;
                        panels.start_child = left_viewport;
                        inner.end_child = right_viewport;
                        panel_width = inner_width = 0;
                    }
                }
                if (!compact && inner.get_width () > 0 && inner_width != inner.get_width ()) {
                    inner_width = inner.get_width ();
                    updating_inner = true;
                    inner.position = (int) (inner_width * detail_proportion);
                    updating_inner = false;
                }
                return Source.CONTINUE;
            });
            notices.child = navigation_overlay;
            notices.vexpand = true;
            root.append (notices);
            root.append (new Gtk.Separator (Gtk.Orientation.HORIZONTAL));
            root.append (build_controls ());
            content = root;
            var shortcuts = new Gtk.ShortcutController ();
            shortcuts.scope = Gtk.ShortcutScope.MANAGED;
            shortcuts.add_shortcut (new Gtk.Shortcut (new Gtk.KeyvalTrigger (Gdk.Key.f, Gdk.ModifierType.CONTROL_MASK),
                new Gtk.CallbackAction ((widget, args) => { return search.grab_focus (); })));
            shortcuts.add_shortcut (new Gtk.Shortcut (new Gtk.KeyvalTrigger (Gdk.Key.z, Gdk.ModifierType.CONTROL_MASK),
                new Gtk.CallbackAction ((widget, args) => { return queue.undo_clear (); })));
            shortcuts.add_shortcut (new Gtk.Shortcut (new Gtk.KeyvalTrigger (Gdk.Key.w, Gdk.ModifierType.CONTROL_MASK),
                new Gtk.CallbackAction ((widget, args) => { close (); return true; })));
            ((Gtk.Widget) this).add_controller (shortcuts);
            var drag_keys = new Gtk.EventControllerKey ();
            drag_keys.propagation_phase = Gtk.PropagationPhase.CAPTURE;
            drag_keys.key_pressed.connect ((keyval, keycode, modifiers) => {
                if (keyval != Gdk.Key.Escape || MediaRow.active_drag == null) return false;
                // GDK can still deliver an already negotiated drop after cancellation.
                if (MediaRow.active_payload != null) MediaRow.active_payload.cancelled = true;
                MediaRow.active_drag.cancel ();
                if (drop_scroll != 0) { Source.remove (drop_scroll); drop_scroll = 0; }
                clear_drop_indicator ();
                return true;
            });
            ((Gtk.Widget) this).add_controller (drag_keys);
            refresh_queue ();
            update_player ();
        }

        private Gtk.Widget build_artist_card () {
            artist_card = new Gtk.Box (Gtk.Orientation.VERTICAL, 8);
            artist_card.add_css_class ("card");
            artist_card.margin_top = artist_card.margin_bottom = 12;
            artist_card.append (title_label ("Sobre el artista"));
            artist_portrait = new Gtk.Image.from_icon_name ("avatar-default-symbolic");
            artist_portrait.name = "artist-portrait";
            artist_portrait.pixel_size = 192;
            artist_portrait.halign = Gtk.Align.CENTER;
            artist_portrait.tooltip_text = "Retrato del artista";
            artist_card.append (artist_portrait);
            artist_name = title_label ("");
            artist_name.wrap = true;
            artist_card.append (artist_name);
            photo_status = text_label ("Expandí un artista o seleccioná un álbum para ver su retrato público");
            photo_status.wrap = true;
            artist_card.append (photo_status);
            photo_author = text_label ("");
            photo_author.wrap = true;
            photo_author.selectable = true;
            photo_author.visible = false;
            artist_card.append (photo_author);
            photo_license = new Gtk.LinkButton.with_label ("", "Licencia");
            photo_license.halign = Gtk.Align.START;
            photo_license.visible = false;
            artist_card.append (photo_license);
            photo_source = new Gtk.LinkButton.with_label ("", "Fuente: Wikimedia Commons");
            photo_source.halign = Gtk.Align.START;
            photo_source.visible = false;
            artist_card.append (photo_source);
            return artist_card;
        }

        private void select_artist (string? artist) {
            if (closed || (artist != null && artist == portrait_artist)) return;
            if (photo_cancel != null) photo_cancel.cancel ();
            photo_cancel = null;
            portrait_artist = artist;
            artist_portrait.set_from_icon_name ("avatar-default-symbolic");
            artist_name.label = artist ?? "";
            photo_author.label = "";
            photo_author.visible = photo_license.visible = photo_source.visible = false;
            photo_license.uri = photo_source.uri = "";
            photo_status.visible = true;
            photo_status.label = "Expandí un artista o seleccioná un álbum para ver su retrato público";
            if (artist == null || artist.strip () == "") return;
            photo_status.label = "Sin retrato disponible. Probá con otro artista de la biblioteca.";
            if (photos == null) return;
            var cached = photo_cache.lookup (artist);
            if (cached != null) {
                try {
                    display_artist_photo (cached);
                } catch (Error e) {
                    photo_status.label = "No se pudo cargar el retrato. Probá con otro artista de la biblioteca.";
                }
                return;
            }
            photo_status.label = "Buscando retrato público…";
            var request = new Cancellable ();
            photo_cancel = request;
            load_artist_photo.begin (artist, request);
        }

        private async void load_artist_photo (string artist, Cancellable request) {
            try {
                var photo = yield photos.fetch (artist, request);
                if (closed || request.is_cancelled () || photo_cancel != request) return;
                photo_status.label = "Sin retrato disponible. Probá con otro artista de la biblioteca.";
                if (photo != null) {
                    display_artist_photo (photo);
                    // At most twelve downloaded portraits (the provider caps each at 5 MiB).
                    if (photo_cache.size () >= 12) photo_cache.remove_all ();
                    photo_cache.insert (artist, photo);
                }
            } catch (Error e) {
                if (!closed && !request.is_cancelled () && photo_cancel == request)
                    photo_status.label = "No se pudo cargar el retrato. Probá con otro artista de la biblioteca.";
            } finally {
                if (photo_cancel == request) photo_cancel = null;
            }
        }

        private void display_artist_photo (ArtistPhoto photo) throws Error {
            var texture = Gdk.Texture.from_bytes (photo.bytes);
            artist_portrait.set_from_paintable (texture);
            photo_author.label = photo.author;
            photo_license.label = photo.license_name;
            photo_license.uri = photo.license_url;
            photo_source.uri = photo.source_url;
            photo_author.visible = photo_license.visible = photo_source.visible = true;
            photo_status.visible = false;
        }

        private Gtk.Widget build_controls () {
            var bar = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 12);
            bar.name = "controls";
            bar.margin_start = bar.margin_end = 12;
            bar.margin_top = bar.margin_bottom = 6;
            var current = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 12);
            current.width_request = 240;
            now_cover = new Gtk.Image.from_icon_name ("audio-x-generic-symbolic");
            now_cover.name = "now-cover";
            now_cover.pixel_size = 48;
            current.append (now_cover);
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
                        if (queue.entries.length == 0) queue.append (visible_tracks);
                        queue.select (0);
                    }
                    player.play ();
                }
            });
            buttons.append (play_button);
            next_button = icon_button ("media-skip-forward-symbolic", "Siguiente");
            next_button.clicked.connect (() => { player.next (); });
            buttons.append (next_button);
            stop_button = icon_button ("media-playback-stop-symbolic", "Detener");
            stop_button.clicked.connect (() => { player.stop (); });
            buttons.append (stop_button);
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
            position_scale.update_property (Gtk.AccessibleProperty.LABEL, "Posición de reproducción", -1);
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
            volume.update_property (Gtk.AccessibleProperty.LABEL, "Volumen", -1);
            volume.set_value (player.volume);
            volume.value_changed.connect (() => { player.volume = volume.get_value (); });
            var volume_spacer = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
            volume_spacer.hexpand = true;
            volume_box.append (volume_spacer);
            volume_box.append (new Gtk.Image.from_icon_name ("audio-volume-high-symbolic"));
            volume_box.append (volume);
            bar.append (volume_box);
            var options = new Gtk.MenuButton ();
            playback_options = options;
            options.valign = Gtk.Align.CENTER;
            options.icon_name = "view-more-symbolic";
            options.tooltip_text = "Opciones de reproducción";
            var popover = new Gtk.Popover ();
            stop_after = new Gtk.CheckButton.with_label ("Detener al terminar esta canción");
            stop_after.name = "stop-after-current";
            stop_after.toggled.connect (() => { player.stop_after_current = stop_after.active; });
            player.notify["stop-after-current"].connect (() => {
                if (closed) return;
                stop_after.active = player.stop_after_current;
                options.icon_name = player.stop_after_current ? "alarm-symbolic" : "view-more-symbolic";
                options.tooltip_text = player.stop_after_current ? "Se detendrá al terminar esta canción; abrir para cancelar" : "Opciones de reproducción";
            });
            popover.child = stop_after;
            options.popover = popover;
            // Keep the footer's two side groups balanced.
            ((Gtk.Box) volume.get_parent ()).append (options);
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
            toast.priority = Adw.ToastPriority.HIGH;
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

        private void stop_watching () {
            watched_uri = null;
            refresh_pending = false;
            if (refresh_timer != 0) { Source.remove (refresh_timer); refresh_timer = 0; }
            if (fallback_timer != 0) { Source.remove (fallback_timer); fallback_timer = 0; }
            directory_monitors.foreach ((uri, monitor) => { monitor.cancel (); });
            directory_monitors.remove_all ();
        }

        private void schedule_refresh () {
            if (closed || watched_uri == null) return;
            refresh_pending = true;
            if (refresh_timer != 0) Source.remove (refresh_timer);
            refresh_timer = Timeout.add (1500, () => {
                refresh_timer = 0;
                if (!loading && !closed && watched_uri != null) {
                    refresh_pending = false;
                    load_library.begin (watched_uri, true);
                }
                return Source.REMOVE;
            });
        }

        protected virtual uint fallback_interval_seconds () { return 900; }

        private void enable_fallback () {
            if (fallback_timer != 0) return;
            // Remote backends may accept a monitor without delivering all changes.
            fallback_timer = Timeout.add_seconds (fallback_interval_seconds (), () => {
                if (!loading && !refresh_pending) schedule_refresh ();
                return Source.CONTINUE;
            });
        }

        private bool watch_directory (File folder) {
            string uri = folder.get_uri ();
            if (directory_monitors.contains (uri)) return false;
            try {
                // Created on GTK's context, so events and all state stay on GTK.
                var monitor = folder.monitor_directory (FileMonitorFlags.WATCH_MOVES, null);
                monitor.changed.connect ((file, other, event) => {
                    if (closed || watched_uri == null) return;
                    if (event == FileMonitorEvent.PRE_UNMOUNT || event == FileMonitorEvent.UNMOUNTED)
                        enable_fallback ();
                    if (file.equal (folder) && (event == FileMonitorEvent.DELETED ||
                        event == FileMonitorEvent.MOVED_OUT || event == FileMonitorEvent.RENAMED)) {
                        // A watch on a removed directory cannot detect its later recreation.
                        enable_fallback ();
                        var removed = directory_monitors.lookup (uri);
                        if (removed != null) removed.cancel ();
                        directory_monitors.remove (uri);
                    }
                    schedule_refresh ();
                });
                directory_monitors.insert (uri, monitor);
                return true;
            } catch (Error e) {
                enable_fallback ();
                return false;
            }
        }

        private void watch_snapshot (File[] directories) {
            var present = new HashTable<string, bool> (str_hash, str_equal);
            bool added = false;
            foreach (var folder in directories) {
                present.insert (folder.get_uri (), true);
                if (watch_directory (folder)) added = true;
            }
            directory_monitors.foreach_remove ((uri, monitor) => {
                if (present.contains (uri)) return false;
                monitor.cancel ();
                return true;
            });
            // Cover changes between enumeration and installation of new watches.
            // Once topology settles this runs once, not a polling loop.
            if (added) schedule_refresh ();
        }

        protected virtual async Track[] scan_source (Scanner scanner, File folder,
                                                     Cancellable cancel, Track[] previous) throws Error {
            return yield scanner.scan (folder, cancel, previous);
        }

        protected virtual async void mount_source (File folder, Cancellable cancel) throws Error {
            var operation = new Gtk.MountOperation (this);
            operation.password_save = PasswordSave.NEVER;
            operation.reply.connect ((result) => { operation.password_save = PasswordSave.NEVER; });
            try { yield folder.mount_enclosing_volume (MountMountFlags.NONE, operation, cancel); }
            catch (IOError.ALREADY_MOUNTED e) { }
        }

        public async void load_library (string input, bool automatic = false) {
            if (loading || closed) return;
            loading = true;
            cancel_button.sensitive = true;
            if (!automatic && preferences.visible) cancel_button.grab_focus ();
            load_button.sensitive = location.sensitive = reload_button.sensitive = browse_button.sensitive = false;
            spinner.start ();
            preference_status.label = "Leyendo biblioteca…";
            if (library.length == 0) {
                empty_title = "Leyendo biblioteca…";
                empty_hint = "La música aparecerá aquí al terminar la carga";
                heading.label = empty_title;
                selection_hint.label = empty_hint;
            }
            scan_cancel = new Cancellable ();
            try {
                var folder = LocationSettings.parse_location (input);
                string uri = folder.get_uri ();
                if (watched_uri != uri) {
                    stop_watching ();
                    watched_uri = uri;
                    if (!folder.is_native ()) enable_fallback ();
                }
                // Root is watched before cache I/O and before the first enumeration.
                watch_directory (folder);
                bool cache_loaded;
                var previous = yield read_cache (uri, out cache_loaded);
                if (closed) return;
                scan_cancel.set_error_if_cancelled ();
                if (previous.length > 0 && library_uri != uri)
                    apply_library (previous, uri);
                var scanner = new Scanner ();
                Track[] loaded;
                try {
                    loaded = yield scan_source (scanner, folder, scan_cancel, previous);
                } catch (IOError.NOT_MOUNTED e) {
                    if (closed) return;
                    if (automatic && previous.length > 0) {
                        preference_status.label = "Ubicación sin montar. Se conserva la biblioteca anterior.";
                        return;
                    }
                    // Background retries must not prompt for a mount.
                    if (automatic) throw e;
                    preference_status.label = "Conectando con la ubicación…";
                    yield mount_source (folder, scan_cancel);
                    loaded = yield scan_source (scanner, folder, scan_cancel, previous);
                }
                if (closed) return;
                scan_cancel.set_error_if_cancelled ();
                watch_snapshot (scanner.get_directories ());
                empty_title = "Biblioteca vacía";
                empty_hint = "Elegí una ubicación con música en Preferencias";
                apply_library (loaded, uri, automatic);
                location.text = uri;
                preference_status.label = (library.length == 1 ? "%u pista cargada" : "%u pistas cargadas").printf (library.length) +
                    " · " + (scanner.skipped == 1 ? "%u archivo de audio omitido" : "%u archivos de audio omitidos").printf (scanner.skipped);
                try {
                    scan_cancel.set_error_if_cancelled ();
                    yield write_cache (uri, loaded, previous, cache_loaded, scan_cancel);
                } catch (IOError.CANCELLED e) {
                    throw e;
                } catch (Error e) {
                    if (!closed)
                        show_error ("No se pudo guardar la caché. Revisá Preferencias.", e.message);
                }
            } catch (IOError.CANCELLED e) {
                if (!closed) {
                    preference_status.label = "Carga cancelada. Se conserva la biblioteca anterior.";
                    if (library.length == 0) {
                        empty_title = "Carga cancelada";
                        empty_hint = "Volvé a cargar la biblioteca desde Preferencias";
                        heading.label = empty_title;
                        selection_hint.label = empty_hint;
                    }
                }
            } catch (Error e) {
                if (!closed) {
                    if (watched_uri != null) enable_fallback ();
                    if (library.length == 0) {
                        empty_title = "No se pudo cargar la biblioteca";
                        empty_hint = "Revisá la ubicación en Preferencias y volvé a cargar";
                        heading.label = empty_title;
                        selection_hint.label = empty_hint;
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
                    if (refresh_pending && refresh_timer == 0) schedule_refresh ();
                }
            }
        }

        private async Track[] read_cache (string uri, out bool loaded) {
            Track[] known = {};
            bool valid = false;
            new Thread<void*> ("library-cache-read", () => {
                try {
                    known = cache.load (uri);
                    valid = true;
                }
                catch (Error e) { /* Missing or corrupt cache must not prevent a scan. */ }
                Idle.add (() => { read_cache.callback (); return Source.REMOVE; });
                return null;
            });
            yield;
            loaded = valid;
            return known;
        }

        private async void write_cache (string uri, Track[] loaded, Track[] previous,
                                        bool cache_loaded, Cancellable cancel) throws Error {
            Error? failure = null;
            new Thread<void*> ("library-cache-write", () => {
                try {
                    if (!cache_loaded || !LibraryCache.same_contents (previous, loaded, cancel))
                        cache.save (uri, loaded, cancel);
                    cancel.set_error_if_cancelled ();
                }
                catch (Error e) { failure = e; }
                Idle.add (() => { write_cache.callback (); return Source.REMOVE; });
                return null;
            });
            yield;
            if (failure != null) throw failure;
        }

        private void apply_library (Track[] loaded, string uri, bool preserve = false) {
            // Cache and scan results share the same stable album order.
            var ordered = new List<Track> ();
            foreach (var track in loaded) ordered.append (track);
            ordered.sort (Scanner.compare_tracks);
            if (preserve && library_uri == uri && same_snapshot (ordered)) return;
            string? selected_uri = (track_selection.selected_item is Track) ? ((Track) track_selection.selected_item).uri : null;
            library = {};
            foreach (var track in ordered) library += track;
            library_uri = uri;
            rebuild_groups (preserve);
            if (preserve && selected_uri != null) {
                for (int i = 0; i < visible_tracks.length; i++) {
                    if (visible_tracks[i].uri != selected_uri) continue;
                    track_selection.selected = (uint) i;
                    break;
                }
            }
            reconcile_queue_artwork ();
            library_updated ();
        }

        private void reconcile_queue_artwork () {
            var known = new HashTable<string, Track> (str_hash, str_equal);
            foreach (var track in library) known.insert (track.uri, track);
            foreach (var entry in queue.entries) {
                var track = known.lookup (entry.track.uri);
                if (track != null) entry.track.cover_data = track.cover_data;
            }
            update_player ();
        }

        private bool same_snapshot (List<Track> ordered) {
            if (ordered.length () != library.length) return false;
            int i = 0;
            foreach (var track in ordered) {
                var previous = library[i++];
                if (track.uri != previous.uri || track.title != previous.title ||
                    track.artist != previous.artist || track.album != previous.album ||
                    track.number != previous.number || track.duration != previous.duration) return false;
                if (track.cover_data != previous.cover_data && (track.cover_data == null ||
                    previous.cover_data == null || track.cover_data.compare (previous.cover_data) != 0)) return false;
            }
            return true;
        }

        private Gtk.SignalListItemFactory media_factory (string kind) {
            var factory = new Gtk.SignalListItemFactory ();
            factory.setup.connect ((obj) => {
                var item = (Gtk.ListItem) obj;
                var row = new MediaRow (kind == "album", kind == "queue", kind == "artist");
                row.requested.connect ((action) => {
                    if (row.entry_id != null) {
                        int index = queue.find (row.entry_id);
                        if (action == "play-entry") player.activate (index);
                        else if (action == "remove") queue.remove (index);
                        else if (action == "up") queue.move (index, index - 1);
                        else if (action == "down") queue.move (index, index + 1);
                    } else music_action (row.tracks, action);
                });
                item.child = row;
            });
            factory.bind.connect ((obj) => {
                var item = (Gtk.ListItem) obj;
                var row = (MediaRow) item.child;
                if (kind == "queue") {
                    var entry = (QueueEntry) item.item;
                    int i = queue.find (entry.id);
                    row.bind_track (entry.track, entry.id, i == queue.index ? "Actual" : i < queue.index ? "Anterior" : "Pendiente");
                } else if (kind == "track") row.bind_track ((Track) item.item);
                else row.bind_group ((LibraryGroup) item.item, kind == "artist");
            });
            factory.unbind.connect ((obj) => { ((MediaRow) ((Gtk.ListItem) obj).child).unbind (); });
            return factory;
        }

        private void music_action (Track[] selected, string action) {
            if (selected.length == 0) return;
            if (action == "append") queue.append (selected);
            else {
                int inserted = queue.insert_next (selected);
                if (action == "now") player.activate (inserted);
            }
        }

        private void navigate_library (int mode) {
            string page = new string[] {"albums", "artists", "songs"}[mode];
            if (page != browsing_page || browser_stack.visible_child_name != page || selected_album != null || selected_artist != null) {
                browsing_page = page;
                rebuild_groups ();
            }
            navigation_overlay.show_sidebar = false;
        }

        private void go_back_in_library () {
            if (browsing_page == "artists" && selected_album != null && selected_artist != null) {
                for (uint i = 0; i < artist_store.get_n_items (); i++) {
                    var artist = (LibraryGroup) artist_store.get_item (i);
                    if (artist.artist == selected_artist) { open_artist (artist); return; }
                }
            }
            rebuild_groups ();
        }

        private void set_library_page (owned string page) {
            browsing_page = page;
            visible_tracks = filtered_tracks ();
            update_player ();
            selected_artist = selected_album = null;
            library_back.visible = false;
            if (page == "songs") show_tracks (filtered_tracks (), "Todas las pistas");
            else {
                select_artist (null);
                heading.label = page == "artists" ? "Artistas" : "Álbumes";
                selection_hint.label = page == "artists" ? "Elegí un artista para explorar sus álbumes" : "Elegí un álbum para ver sus canciones";
                cover.set_from_icon_name ("audio-x-generic-symbolic");
                cover.pixel_size = 96;
                album_color = null;
                update_album_style ();
                browser_stack.visible_child_name = page;
            }
            if (library.length == 0) {
                heading.label = empty_title;
                selection_hint.label = empty_hint;
            } else if (visible_tracks.length == 0) {
                heading.label = "Sin resultados";
                selection_hint.label = "Probá con otro título, artista o álbum";
            }
            navigation_overlay.show_sidebar = false;
        }

        private Track[] filtered_tracks () {
            Track[] result = {};
            string query = search.text.casefold ().strip ();
            foreach (var track in library)
                if (query == "" || track.title.casefold ().contains (query) || track.artist.casefold ().contains (query) || track.album.casefold ().contains (query))
                    result += track;
            return result;
        }

        private void rebuild_groups (bool preserve = false) {
            var albums = new HashTable<string, LibraryGroup> (str_hash, str_equal);
            var artists = new HashTable<string, LibraryGroup> (str_hash, str_equal);
            var ordered_albums = new List<LibraryGroup> ();
            var ordered_artists = new List<LibraryGroup> ();
            foreach (var track in filtered_tracks ()) {
                // Length-prefixed exact keys keep homonyms and Unicode spellings distinct.
                string id = "%u:%s%s".printf (track.artist.length, track.artist, track.album);
                var album = albums.lookup (id);
                if (album == null) {
                    album = new LibraryGroup (track.album, track.artist);
                    albums.insert (id, album);
                    ordered_albums.append (album);
                }
                album.add (track);
                var artist = artists.lookup (track.artist);
                if (artist == null) {
                    artist = new LibraryGroup (track.artist, track.artist);
                    artists.insert (track.artist, artist);
                    ordered_artists.append (artist);
                }
                artist.add (track);
            }
            Object[] album_items = {};
            Object[] artist_items = {};
            foreach (var album in ordered_albums) album_items += album;
            foreach (var artist in ordered_artists) artist_items += artist;
            album_store.splice (0, album_store.get_n_items (), album_items);
            artist_store.splice (0, artist_store.get_n_items (), artist_items);
            if (preserve && selected_album != null) {
                Track[] selected = {};
                foreach (var track in filtered_tracks ())
                    if (track.artist == selected_artist && track.album == selected_album) selected += track;
                if (selected.length > 0) { show_tracks (selected, selected_album + " — " + selected_artist, true); return; }
            }
            if (preserve && browsing_page == "artists" && selected_artist != null) {
                var artist = artists.lookup (selected_artist);
                if (artist != null) { open_artist (artist); return; }
            }
            set_library_page (browsing_page);
        }

        private void open_album (LibraryGroup album) {
            selected_artist = album.artist;
            selected_album = album.title;
            library_back.visible = true;
            show_tracks (album.tracks, album.title + " — " + album.artist, true);
        }

        private void open_artist (LibraryGroup artist) {
            selected_artist = artist.artist;
            selected_album = null;
            visible_tracks = artist.tracks;
            library_back.visible = true;
            cover.set_from_icon_name ("audio-x-generic-symbolic");
            cover.pixel_size = 96;
            album_color = null;
            update_album_style ();
            select_artist (artist.artist);
            album_store.remove_all ();
            var albums = new HashTable<string, LibraryGroup> (str_hash, str_equal);
            foreach (var track in artist.tracks) {
                var album = albums.lookup (track.album);
                if (album == null) {
                    album = new LibraryGroup (track.album, track.artist);
                    albums.insert (track.album, album);
                }
                album.add (track);
            }
            // Traverse already sorted tracks for stable album order.
            string? last = null;
            foreach (var track in artist.tracks) {
                if (track.album != last) album_store.append (albums.lookup (track.album));
                last = track.album;
            }
            heading.label = artist.title;
            selection_hint.label = "Elegí un álbum para ver sus canciones";
            browser_stack.visible_child_name = "albums";
        }

        public async void import_files (File[] sources, int insertion = -1) {
            if (import_cancel != null || closed) return;
            var cancel = new Cancellable ();
            import_cancel = cancel;
            string? anchor = insertion >= 0 && insertion < queue.entries.length ? queue.entries[insertion].id : null;
            import_activity.visible = true;
            import_spinner.start ();
            import_status.label = "Preparando archivos para la cola…";
            try {
                var scanner = new Scanner ();
                var imported = yield scanner.import_sources (sources, cancel);
                if (closed) return;
                cancel.set_error_if_cancelled ();
                int position = anchor == null ? queue.entries.length : queue.find (anchor);
                queue.insert (imported, position < 0 ? queue.entries.length : position);
                var toast = new Adw.Toast ((imported.length == 1 ? "%u pista agregada" : "%u pistas agregadas").printf (imported.length) +
                    " · " + (scanner.skipped == 1 ? "%u archivo omitido" : "%u archivos omitidos").printf (scanner.skipped));
                toast.use_markup = false;
                notices.add_toast (toast);
            } catch (IOError.CANCELLED e) {
                if (!closed) notices.add_toast (new Adw.Toast ("Importación cancelada"));
            } catch (Error e) {
                if (!closed) show_error ("No se pudieron importar los archivos. Revisá Preferencias.", e.message);
            } finally {
                if (!closed) { import_spinner.stop (); import_activity.visible = false; }
                import_cancel = null;
            }
        }

        private async void choose_import (bool folders) {
            var dialog = new Gtk.FileDialog ();
            dialog.title = folders ? "Agregar carpetas a la cola" : "Agregar archivos a la cola";
            try {
                ListModel selected;
                if (folders) selected = yield dialog.select_multiple_folders (this, null);
                else selected = yield dialog.open_multiple (this, null);
                File[] files = {};
                for (uint i = 0; i < selected.get_n_items (); i++) files += (File) selected.get_item (i);
                if (!closed) yield import_files (files);
            } catch (Error e) { }
        }

        private void clear_queue () {
            if (!queue.clear ()) return;
            var toast = new Adw.Toast (queue.current == null ? "Cola vaciada" : "Cola vaciada; se conserva la canción actual");
            toast.button_label = "Deshacer";
            toast.button_clicked.connect (() => { queue.undo_clear (); });
            notices.add_toast (toast);
        }

        private void clear_drop_indicator () {
            if (drop_row != null) drop_row.insertion (0);
            drop_row = null;
        }
        private int insertion_at (double x, double y) {
            clear_drop_indicator ();
            Graphene.Point point;
            if (!queue_drop_area.compute_point (queue_list, Graphene.Point () { x = (float) x, y = (float) y }, out point))
                return queue.entries.length;
            x = point.x;
            y = point.y;
            var picked = queue_list.pick (x, y, Gtk.PickFlags.DEFAULT);
            while (picked != null && !(picked is MediaRow)) picked = picked.get_parent ();
            var row = picked as MediaRow;
            if (row == null || row.entry_id == null) return queue.entries.length;
            Graphene.Rect bounds;
            if (!row.compute_bounds (queue_list, out bounds)) return queue.entries.length;
            bool after = y > bounds.get_y () + bounds.get_height () / 2;
            drop_row = row;
            row.insertion (after ? 1 : -1);
            return queue.find (row.entry_id) + (after ? 1 : 0);
        }
        private void install_queue_drop (Gtk.ScrolledWindow viewport) {
            var target = new Gtk.DropTarget (typeof (QueueDrag), Gdk.DragAction.COPY | Gdk.DragAction.MOVE);
            target.propagation_phase = Gtk.PropagationPhase.CAPTURE;
            target.preload = true;
            target.set_gtypes ({typeof (QueueDrag), typeof (Gdk.FileList)});
            target.motion.connect ((x, y) => {
                drop_x = x; drop_y = y;
                insertion_at (x, y);
                if (drop_scroll == 0) drop_scroll = Timeout.add (40, () => {
                    double local = drop_y;
                    var adjustment = viewport.vadjustment;
                    double step = local < 40 ? -16 : local > viewport.get_height () - 40 ? 16 : 0;
                    adjustment.value = (adjustment.value + step).clamp (adjustment.lower, double.max (adjustment.lower, adjustment.upper - adjustment.page_size));
                    insertion_at (drop_x, drop_y);
                    return Source.CONTINUE;
                });
                unowned Value? value = target.get_value ();
                return value != null && value.holds (typeof (QueueDrag)) && ((QueueDrag) value.get_object ()).entry_id != null ? Gdk.DragAction.MOVE : Gdk.DragAction.COPY;
            });
            target.leave.connect (() => {
                clear_drop_indicator ();
                if (drop_scroll != 0) { Source.remove (drop_scroll); drop_scroll = 0; }
            });
            target.on_drop.connect ((value, x, y) => {
                int position = insertion_at (x, y);
                clear_drop_indicator ();
                if (drop_scroll != 0) { Source.remove (drop_scroll); drop_scroll = 0; }
                if (value.holds (typeof (QueueDrag))) {
                    var data = (QueueDrag) value.get_object ();
                    if (data.cancelled) return false;
                    if (data.entry_id == null) queue.insert (data.tracks, position);
                    else {
                        int from = queue.find (data.entry_id);
                        if (from >= 0) queue.move (from, (position > from ? position - 1 : position).clamp (0, queue.entries.length - 1));
                    }
                    return true;
                }
                if (value.holds (typeof (Gdk.FileList))) {
                    File[] sources = {};
                    foreach (var file in ((Gdk.FileList) value.get_boxed ()).get_files ()) sources += file;
                    import_files.begin (sources, position);
                    return true;
                }
                return false;
            });
            queue_drop_area.add_controller (target);
            var keys = new Gtk.EventControllerKey ();
            keys.key_pressed.connect ((keyval, keycode, modifiers) => {
                uint selected = queue_selection.selected;
                if (selected == Gtk.INVALID_LIST_POSITION) return false;
                if (keyval == Gdk.Key.Delete) return queue.remove ((int) selected);
                if ((modifiers & Gdk.ModifierType.ALT_MASK) != 0) {
                    if (keyval == Gdk.Key.Up) return queue.move ((int) selected, (int) selected - 1);
                    if (keyval == Gdk.Key.Down) return queue.move ((int) selected, (int) selected + 1);
                }
                return false;
            });
            queue_list.add_controller (keys);
        }

        private void show_tracks (Track[] selection, string title, bool album_selected = false) {
            select_artist (album_selected && selection.length > 0 ? selection[0].artist : null);
            cover.set_from_icon_name ("audio-x-generic-symbolic");
            cover.pixel_size = album_selected ? 192 : 96;
            album_color = null;
            if (album_selected) {
                foreach (var track in selection) {
                    if (track.cover_data == null) continue;
                    try {
                        var texture = Gdk.Texture.from_bytes (track.cover_data);
                        cover.set_from_paintable (texture);
                        extract_album_color (texture);
                        break;
                    } catch (Error e) { }
                }
            }
            update_album_style ();
            visible_tracks = selection;
            track_store.remove_all ();
            browser_stack.visible_child_name = "songs";
            heading.label = selection.length == 0 ? (search.text == "" ? "Biblioteca vacía" : "Sin resultados") :
                title + (selection.length == 1 ? " · %u pista" : " · %u pistas").printf (selection.length);
            if (library.length == 0) heading.label = empty_title;
            selection_hint.label = selection.length == 0 ? (library.length == 0 ? empty_hint : "Probá con otra búsqueda") :
                "Activá una canción para insertarla a continuación y reproducirla";
            foreach (var track in selection) track_store.append (track);
            update_player ();
        }
        private void extract_album_color (Gdk.Texture texture) {
            var sample = Gdk.pixbuf_get_from_texture (texture).scale_simple (16, 16, Gdk.InterpType.BILINEAR);
            unowned uint8[] pixels = sample.get_pixels ();
            double red = 0, green = 0, blue = 0, total = 0;
            for (int y = 0; y < sample.height; y++) {
                for (int x = 0; x < sample.width; x++) {
                    int offset = y * sample.rowstride + x * sample.n_channels;
                    double r = pixels[offset] / 255.0;
                    double g = pixels[offset + 1] / 255.0;
                    double b = pixels[offset + 2] / 255.0;
                    double weight = 0.05 + double.max (r, double.max (g, b)) - double.min (r, double.min (g, b));
                    if (sample.has_alpha) weight *= pixels[offset + 3] / 255.0;
                    red += r * weight;
                    green += g * weight;
                    blue += b * weight;
                    total += weight;
                }
            }
            if (total > 0) {
                album_color = Gdk.RGBA () {
                    red = (float) (red / total), green = (float) (green / total),
                    blue = (float) (blue / total), alpha = 1
                };
            }
        }

        private void update_album_style () {
            if (album_color == null || theme.high_contrast) {
                album_style.load_from_data ("".data);
                return;
            }
            var tint = album_color;
            tint.alpha = theme.dark ? 0.36f : 0.22f;
            // Only these two widget contexts use this provider; other windows keep their theme.
            string css = ".album-backdrop { background-image: linear-gradient(to bottom, %s 0px, transparent 420px); }\n".printf (tint.to_string ()) +
                "headerbar { background: transparent; box-shadow: none; }";
            album_style.load_from_data (css.data);
        }

        private void refresh_queue () {
            string? selected = (queue_selection.selected_item is QueueEntry) ? ((QueueEntry) queue_selection.selected_item).id : null;
            string? active = queue.current_entry == null ? null : queue.current_entry.id;
            if (active != displayed_current) selected = active;
            displayed_current = active;
            Object[] items = {};
            foreach (var entry in queue.entries) items += entry;
            queue_store.splice (0, queue_store.get_n_items (), items);
            int selected_index = selected == null ? -1 : queue.find (selected);
            queue_selection.selected = selected_index < 0 ? Gtk.INVALID_LIST_POSITION : (uint) selected_index;
            queue_empty.visible = queue.entries.length == 0;
            queue_count.label = (queue.entries.length == 1 ? "%u pista" : "%u pistas").printf (queue.entries.length);
            clear_button.sensitive = queue.entries.length > (queue.current == null ? 0 : 1);
            undo_button.sensitive = queue.can_undo;
        }
        private void update_player () {
            if (closed) return;
            play_button.icon_name = player.state == Gst.State.PLAYING ? "media-playback-pause-symbolic" : "media-playback-start-symbolic";
            var track = queue.current;
            play_button.sensitive = track != null || visible_tracks.length > 0;
            previous_button.sensitive = track != null && queue.index > 0;
            next_button.sensitive = track != null && queue.index + 1 < queue.entries.length;
            stop_button.sensitive = track != null;
            if (playback_options != null) playback_options.sensitive = track != null;
            if (stop_after != null) stop_after.active = player.stop_after_current;
            if (track == null) {
                now_cover_data = null;
                now_playing.label = "Nada en reproducción";
                now_cover.set_from_icon_name ("audio-x-generic-symbolic");
                now_cover_uri = null;
                return;
            }
            if (now_cover_uri != track.uri || now_cover_data != track.cover_data) {
                now_cover.set_from_icon_name ("audio-x-generic-symbolic");
                now_cover_uri = track.uri;
                now_cover_data = track.cover_data;
                if (track.cover_data != null) {
                    try { now_cover.set_from_paintable (Gdk.Texture.from_bytes (track.cover_data)); }
                    catch (Error e) { }
                }
            }
            now_playing.label = track.title + "\n" + track.artist;
            info.label = track.title + "\n\nArtista: " + track.artist + "\nÁlbum: " + track.album +
                "\nPista: " + (track.number == 0 ? "Sin número" : track.number.to_string ()) +
                "\nDuración: " + time_text ((double) track.duration / Gst.SECOND) + "\n\n" + track.uri;

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
            button.update_property (Gtk.AccessibleProperty.LABEL, tooltip, -1);
            return button;
        }
        private static string time_text (double seconds) {
            int total = (int) seconds;
            return "%d:%02d".printf (total / 60, total % 60);
        }
    }
}
