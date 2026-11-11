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
        private Gtk.Stack sidebar_stack;
        private Gtk.Button library_back;
        private Gtk.NoSelection album_grid_model;
        private ListStore sidebar_album_store;
        private ListStore artist_store;
        private Gtk.TreeListModel sidebar_album_tree;
        private Gtk.TreeListModel sidebar_artist_tree;
        private Gtk.SingleSelection sidebar_album_selection;
        private Gtk.SingleSelection sidebar_artist_selection;
        private Gtk.ListView sidebar_artists;
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
        private Adw.OverlaySplitView queue_panel_overlay;
        private bool compact;
        private PlayQueue queue = new PlayQueue ();
        private Player player;
        private VisualizerWindow? visualizer;
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
        private Gtk.Label selection_kind;
        private Gtk.Label selection_format;
        private Gtk.Box album_summary;
        private Gtk.Box album_actions;
        private Gtk.Button album_play;
        private Gtk.Button album_append;
        private Gtk.Button album_next;
        private Gtk.MenuButton selection_menu;
        private Gtk.Button show_all_tracks;
        private Gtk.Box queue_empty;
        private ArtistPhotos? photos;
        private HashTable<string, ArtistPhoto> photo_cache = new HashTable<string, ArtistPhoto> (str_hash, str_equal);
        private List<LibrarySidebarRow> artist_rows;
        private HashTable<string, bool> unavailable_thumbnails = new HashTable<string, bool> (str_hash, str_equal);
        private uint thumbnail_idle;
        private Cancellable? thumbnail_cancel;
        private Gtk.Label now_playing;
        private Gtk.Label elapsed_time;
        private Gtk.Label duration_time;
        private Gtk.ListView tracks;
        private Gtk.ListView queue_list;
        private Gtk.Scale position_scale;
        private uint ticker;
        private bool updating_position;
        private bool closed;
        private Gtk.CssProvider library_style = new Gtk.CssProvider ();
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
                if (visualizer != null) { visualizer.close (); visualizer = null; }
                stop_watching ();
                theme.disconnect (dark_changed);
                theme.disconnect (contrast_changed);
                album_style.load_from_data ("".data);
                Gtk.StyleContext.remove_provider_for_display (get_display (), library_style);
                preferences.set_focus (null);
                preferences.destroy ();
                if (scan_cancel != null) scan_cancel.cancel ();
                if (thumbnail_cancel != null) thumbnail_cancel.cancel ();
                if (thumbnail_idle != 0) { Source.remove (thumbnail_idle); thumbnail_idle = 0; }
                if (import_cancel != null) import_cancel.cancel ();
                if (drop_scroll != 0) { Source.remove (drop_scroll); drop_scroll = 0; }
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
            library_style.load_from_data ("""
                .gtkplayer-artwork { background-color: @card_bg_color; border-radius: 8px; }
                .gtkplayer-artist-thumbnail { border-radius: 999px; }
                .gtkplayer-portrait-button > button { min-width: 0; min-height: 0; padding: 0; }
                .gtkplayer-album-tile { min-width: 11.5em; }
                .gtkplayer-library-tabs > button { min-width: 0; padding-left: 10px; padding-right: 10px; }
                .gtkplayer-browser-surface { background-color: transparent; }
                .queue-insertion { min-height: 3px; background-color: @accent_color; }
                """.data);
            Gtk.StyleContext.add_provider_for_display (get_display (), library_style, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION);
            build_preferences ();
            var settings_button = icon_button ("emblem-system-symbolic", "Preferencias");
            settings_button.name = "open-preferences";
            settings_button.clicked.connect (() => {
                location.text = new LocationSettings (config_path).load ();
                preferences.present ();
            });
            header.pack_end (settings_button);
            var visualize = icon_button ("view-reveal-symbolic", "Abrir visualizador");
            visualize.name = "open-visualizer";
            visualize.clicked.connect (() => {
                if (visualizer == null) {
                    visualizer = new VisualizerWindow (this, player);
                    visualizer.close_request.connect (() => { visualizer = null; return false; });
                }
                visualizer.present ();
            });
            header.pack_end (visualize);
            library_back = icon_button ("go-previous-symbolic", "Volver a la biblioteca");
            library_back.name = "library-back";
            library_back.visible = false;
            library_back.clicked.connect (go_back_in_library);
            header.pack_start (library_back);
            spinner = new Gtk.Spinner ();
            header.pack_end (spinner);

            var left = new Gtk.Box (Gtk.Orientation.VERTICAL, 8);
            left.name = "library";
            left.margin_start = left.margin_end = 8;
            left.margin_top = 12;
            sidebar_stack = new Gtk.Stack ();
            sidebar_stack.name = "library-categories";
            sidebar_stack.vexpand = true;
            var categories = new Gtk.StackSwitcher ();
            categories.stack = sidebar_stack;
            categories.name = "library-tabs";
            categories.add_css_class ("gtkplayer-library-tabs");
            categories.update_property (Gtk.AccessibleProperty.LABEL, "Categorías de la biblioteca", -1);
            left.append (categories);
            sidebar_album_store = new ListStore (typeof (LibraryGroup));
            artist_store = new ListStore (typeof (LibraryGroup));
            sidebar_album_tree = new Gtk.TreeListModel (sidebar_album_store, false, false, sidebar_children);
            sidebar_artist_tree = new Gtk.TreeListModel (artist_store, false, false, sidebar_children);
            sidebar_album_selection = new Gtk.SingleSelection (sidebar_album_tree) { autoselect = false, can_unselect = true };
            sidebar_artist_selection = new Gtk.SingleSelection (sidebar_artist_tree) { autoselect = false, can_unselect = true };
            var sidebar_albums = build_sidebar_list (sidebar_album_selection, false);
            sidebar_artists = build_sidebar_list (sidebar_artist_selection, true);
            sidebar_albums.activate.connect ((index) => { activate_sidebar_row (sidebar_album_tree, index, "albums"); });
            sidebar_artists.activate.connect ((index) => { activate_sidebar_row (sidebar_artist_tree, index, "artists"); });
            sidebar_artists.map.connect (schedule_thumbnails);
            sidebar_artists.unmap.connect (() => {
                if (thumbnail_cancel != null) thumbnail_cancel.cancel ();
            });
            sidebar_stack.add_titled (scroll (sidebar_albums), "albums", "Álbumes");
            var artist_scroll = scroll (sidebar_artists);
            artist_scroll.vadjustment.changed.connect (schedule_thumbnails);
            artist_scroll.vadjustment.value_changed.connect (schedule_thumbnails);
            sidebar_stack.add_titled (artist_scroll, "artists", "Artistas");
            left.append (sidebar_stack);

            var center = new Gtk.Box (Gtk.Orientation.VERTICAL, 12);
            center.name = "tracks";
            center.hexpand = true;
            center.margin_start = center.margin_end = 18;
            center.margin_top = 16;
            var summary = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 14);
            album_summary = summary;
            cover = new Gtk.Image.from_icon_name ("audio-x-generic-symbolic");
            cover.set_size_request (144, 144);
            cover.add_css_class ("gtkplayer-artwork");
            cover.overflow = Gtk.Overflow.HIDDEN;
            cover.valign = Gtk.Align.CENTER;
            cover.visible = false;
            summary.append (cover);
            var summary_text = new Gtk.Box (Gtk.Orientation.VERTICAL, 4);
            summary_text.hexpand = true;
            summary_text.valign = Gtk.Align.CENTER;
            selection_kind = text_label ("Álbum");
            selection_kind.add_css_class ("caption");
            selection_kind.visible = false;
            summary_text.append (selection_kind);
            heading = text_label (empty_title);
            heading.add_css_class ("title-1");
            heading.ellipsize = Pango.EllipsizeMode.END;
            heading.tooltip_text = heading.label;
            summary_text.append (heading);
            selection_hint = text_label (empty_hint);
            selection_hint.wrap = true;
            selection_hint.wrap_mode = Pango.WrapMode.WORD_CHAR;
            selection_hint.ellipsize = Pango.EllipsizeMode.END;
            selection_hint.lines = 2;
            summary_text.append (selection_hint);
            selection_format = text_label ("");
            selection_format.name = "album-format";
            selection_format.add_css_class ("dim-label");
            selection_format.add_css_class ("caption");
            selection_format.wrap = true;
            selection_format.wrap_mode = Pango.WrapMode.WORD_CHAR;
            selection_format.visible = false;
            summary_text.append (selection_format);
            summary.append (summary_text);
            center.append (summary);
            album_actions = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
            album_actions.name = "album-controls";
            album_actions.visible = false;
            album_play = icon_button ("media-playback-start-symbolic", "Reproducir álbum");
            album_play.name = "album-play";
            album_play.add_css_class ("circular");
            album_play.add_css_class ("suggested-action");
            album_play.set_size_request (48, 48);
            ((Gtk.Image) album_play.child).pixel_size = 24;
            album_play.clicked.connect (() => {
                if (current_in_album ()) {
                    if (player.state == Gst.State.PLAYING) player.pause ();
                    else player.play ();
                } else music_action (visible_tracks, "now");
            });
            album_actions.append (album_play);
            album_append = icon_button ("list-add-symbolic", "Agregar álbum a la cola");
            album_append.name = "album-append";
            album_append.add_css_class ("flat");
            album_append.set_size_request (48, 48);
            album_append.clicked.connect (() => {
                music_action (visible_tracks, "append");
                notices.add_toast (new Adw.Toast ("Álbum agregado a la cola"));
            });
            album_actions.append (album_append);
            album_next = icon_button ("media-playlist-consecutive-symbolic", "Reproducir álbum a continuación");
            album_next.name = "album-next";
            album_next.add_css_class ("flat");
            album_next.set_size_request (48, 48);
            album_next.clicked.connect (() => {
                music_action (visible_tracks, "next");
                notices.add_toast (new Adw.Toast ("El álbum se reproducirá a continuación"));
            });
            album_actions.append (album_next);
            selection_menu = new Gtk.MenuButton ();
            selection_menu.name = "library-actions";
            selection_menu.icon_name = "view-more-symbolic";
            selection_menu.add_css_class ("flat");
            selection_menu.valign = Gtk.Align.CENTER;
            selection_menu.set_size_request (48, 48);
            selection_menu.visible = false;
            var selection_popover = new Gtk.Popover ();
            var selection_actions = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            foreach (string action in new string[] {"append", "next", "now"}) {
                string selected_action = action;
                var button = new Gtk.Button.with_label (action == "append" ? "Agregar a la cola" : action == "next" ? "Reproducir a continuación" : "Reproducir ahora");
                button.add_css_class ("flat");
                button.clicked.connect (() => {
                    selection_popover.popdown ();
                    music_action (visible_tracks, selected_action);
                });
                selection_actions.append (button);
            }
            show_all_tracks = new Gtk.Button.with_label ("Ver todas las pistas");
            show_all_tracks.name = "show-all-tracks";
            show_all_tracks.add_css_class ("flat");
            show_all_tracks.clicked.connect (() => {
                selection_popover.popdown ();
                set_library_page ("songs");
            });
            selection_actions.append (show_all_tracks);
            selection_popover.child = selection_actions;
            selection_menu.popover = selection_popover;
            summary.append (selection_menu);
            center.append (album_actions);
            search = new Gtk.SearchEntry ();
            search.name = "library-search";
            search.placeholder_text = "Buscar título, artista o álbum";
            search.update_property (Gtk.AccessibleProperty.LABEL, "Buscar en la biblioteca", -1);
            search.search_changed.connect (() => { rebuild_groups (); });
            center.append (search);
            browser_stack = new Gtk.Stack ();
            browser_stack.vexpand = true;
            track_store = new ListStore (typeof (Track));
            track_selection = new Gtk.SingleSelection (track_store);
            track_selection.autoselect = false;
            tracks = new Gtk.ListView (track_selection, media_factory ("track"));
            tracks.name = "song-list";
            tracks.add_css_class ("gtkplayer-browser-surface");
            tracks.show_separators = true;
            tracks.single_click_activate = true;
            tracks.activate.connect ((index) => {
                var track = track_store.get_item (index) as Track;
                if (track != null) music_action ({track}, "now");
            });
            browser_stack.add_named (scroll (tracks), "songs");
            album_grid_model = new Gtk.NoSelection (sidebar_album_store);
            var albums = new Gtk.GridView (album_grid_model, media_factory ("album"));
            albums.name = "album-grid";
            albums.add_css_class ("gtkplayer-browser-surface");
            albums.min_columns = 1;
            albums.max_columns = 8;
            albums.single_click_activate = true;
            albums.activate.connect ((index) => {
                var album = album_grid_model.get_item (index) as LibraryGroup;
                if (album != null) open_album (album);
            });
            browser_stack.add_named (scroll (albums), "albums");
            center.append (browser_stack);

            var right = new Gtk.Box (Gtk.Orientation.VERTICAL, 6);
            right.name = "queue-panel";
            right.margin_start = right.margin_end = 12;
            right.margin_top = 12;
            queue_store = new ListStore (typeof (QueueEntry));
            queue_selection = new Gtk.SingleSelection (queue_store);
            queue_list = new Gtk.ListView (queue_selection, media_factory ("queue"));
            queue_list.name = "queue-list";
            queue_list.add_css_class ("gtkplayer-browser-surface");
            queue_empty = new Gtk.Box (Gtk.Orientation.VERTICAL, 8);
            queue_empty.name = "queue-empty";
            queue_empty.valign = Gtk.Align.CENTER;
            queue_empty.margin_start = queue_empty.margin_end = 12;
            var empty_icon = new Gtk.Image.from_icon_name ("view-list-symbolic");
            empty_icon.pixel_size = 32;
            empty_icon.add_css_class ("dim-label");
            queue_empty.append (empty_icon);
            var queue_title = new Gtk.Label ("Cola vacía");
            queue_title.add_css_class ("heading");
            queue_empty.append (queue_title);
            var queue_hint = new Gtk.Label ("Agregá música desde la biblioteca o importá archivos y carpetas.");
            queue_hint.wrap = true;
            queue_hint.wrap_mode = Pango.WrapMode.WORD_CHAR;
            queue_hint.justify = Gtk.Justification.CENTER;
            queue_empty.append (queue_hint);
            queue_list.single_click_activate = true;
            queue_list.activate.connect ((index) => { player.activate ((int) index); });
            var queue_toolbar = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
            queue_toolbar.add_css_class ("toolbar");
            var queue_heading = new Gtk.Box (Gtk.Orientation.VERTICAL, 2);
            queue_heading.hexpand = true;
            queue_heading.valign = Gtk.Align.CENTER;
            queue_heading.append (title_label ("Cola"));
            queue_count = text_label ("0 pistas");
            queue_count.name = "queue-count";
            queue_count.ellipsize = Pango.EllipsizeMode.END;
            queue_count.add_css_class ("dim-label");
            queue_heading.append (queue_count);
            queue_toolbar.append (queue_heading);
            var add_files = icon_button ("list-add-symbolic", "Agregar archivos a la cola…");
            add_files.clicked.connect (() => { choose_import.begin (false); });
            queue_toolbar.append (add_files);
            var add_folder = icon_button ("folder-open-symbolic", "Agregar carpetas a la cola…");
            add_folder.clicked.connect (() => { choose_import.begin (true); });
            queue_toolbar.append (add_folder);
            clear_button = icon_button ("edit-clear-all-symbolic", "Vaciar cola");
            clear_button.name = "clear-queue";
            clear_button.clicked.connect (clear_queue);
            queue_toolbar.append (clear_button);
            undo_button = icon_button ("edit-undo-symbolic", "Deshacer vaciado");
            undo_button.name = "undo-queue";
            undo_button.clicked.connect (() => { queue.undo_clear (); });
            queue_toolbar.append (undo_button);
            right.append (queue_toolbar);
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
            right.append (import_activity);
            var queue_scroll = scroll (queue_list);

            // The empty placeholder also accepts drops: the list remains allocated behind it.
            var queue_overlay = new Gtk.Overlay ();
            queue_drop_area = queue_overlay;
            queue_overlay.name = "queue-drop-area";
            queue_overlay.child = queue_scroll;
            queue_empty.can_target = false;
            queue_overlay.add_overlay (queue_empty);
            queue_overlay.vexpand = true;
            right.append (queue_overlay);
            install_queue_drop (queue_scroll);
            // Empty-space drops land on the list's full viewport.
            queue_list.vexpand = true;
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
            queue_panel_overlay = new Adw.OverlaySplitView ();
            queue_panel_overlay.collapsed = true;
            queue_panel_overlay.show_sidebar = false;
            queue_panel_overlay.sidebar_position = Gtk.PackType.END;
            queue_panel_overlay.min_sidebar_width = 320;
            queue_panel_overlay.max_sidebar_width = 400;
            queue_panel_overlay.content = panels;
            navigation_overlay = new Adw.OverlaySplitView ();
            navigation_overlay.collapsed = true;
            navigation_overlay.show_sidebar = false;
            navigation_overlay.content = queue_panel_overlay;
            var library_toggle = icon_button ("sidebar-show-symbolic", "Mostrar biblioteca");
            library_toggle.name = "show-library";
            library_toggle.clicked.connect (() => { navigation_overlay.show_sidebar = !navigation_overlay.show_sidebar; });
            header.pack_start (library_toggle);
            var queue_toggle = icon_button ("view-list-symbolic", "Mostrar cola");
            queue_toggle.name = "show-queue";
            queue_toggle.clicked.connect (() => { queue_panel_overlay.show_sidebar = !queue_panel_overlay.show_sidebar; });
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
                        queue_panel_overlay.sidebar = right_viewport;
                    } else {
                        navigation_overlay.show_sidebar = queue_panel_overlay.show_sidebar = false;
                        navigation_overlay.sidebar = queue_panel_overlay.sidebar = null;
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
            shortcuts.add_shortcut (new Gtk.Shortcut (new Gtk.KeyvalTrigger (Gdk.Key.F9, 0),
                new Gtk.CallbackAction ((widget, args) => {
                    if (!compact) return false;
                    queue_toggle.clicked ();
                    return true;
                })));
            shortcuts.add_shortcut (new Gtk.Shortcut (new Gtk.KeyvalTrigger (Gdk.Key.f, Gdk.ModifierType.CONTROL_MASK),
                new Gtk.CallbackAction ((widget, args) => {
                    if (selected_album != null) set_library_page (sidebar_stack.visible_child_name ?? "albums");
                    return search.grab_focus ();
                })));
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
            sidebar_stack.notify["visible-child-name"].connect (() => {
                string? category = sidebar_stack.visible_child_name;
                if (!closed && category != null && category != browsing_page) set_library_page (category);
            });
        }

        private void remember_photo (string artist, ArtistPhoto photo) {
            // At most twelve downloaded portraits (the provider caps each at 5 MiB).
            if (photo_cache.size () >= 12 && !photo_cache.contains (artist)) photo_cache.remove_all ();
            photo_cache.insert (artist, photo);
            unavailable_thumbnails.remove (artist);
        }

        private void remember_unavailable_thumbnail (string artist) {
            if (unavailable_thumbnails.size () >= 256) unavailable_thumbnails.remove_all ();
            unavailable_thumbnails.insert (artist, true);
        }

        private void schedule_thumbnails () {
            if (closed || photos == null || !sidebar_artists.get_mapped () ||
                thumbnail_idle != 0 || thumbnail_cancel != null) return;
            thumbnail_idle = Idle.add (() => {
                thumbnail_idle = 0;
                if (closed || !sidebar_artists.get_mapped ()) return Source.REMOVE;
                foreach (var row in artist_rows) {
                    var group = row.artist_group;
                    if (!row.get_mapped () || row.has_portrait || group == null ||
                        group.artist == "Artista desconocido" || unavailable_thumbnails.contains (group.artist)) continue;
                    Graphene.Rect bounds;
                    if (!row.compute_bounds (sidebar_artists, out bounds) ||
                        bounds.get_y () + bounds.get_height () <= 0 || bounds.get_y () >= sidebar_artists.get_height ()) continue;
                    var photo = photo_cache.lookup (group.artist);
                    if (photo != null) {
                        try { row.show_portrait (Gdk.Texture.from_bytes (photo.bytes), photo); }
                        catch (Error e) { remember_unavailable_thumbnail (group.artist); }
                        continue;
                    }
                    var request = new Cancellable ();
                    thumbnail_cancel = request;
                    load_thumbnail.begin (group.artist, request);
                    break;
                }
                return Source.REMOVE;
            });
        }

        private async void load_thumbnail (string artist, Cancellable request) {
            ArtistPhoto? photo = null;
            Gdk.Texture? texture = null;
            try {
                photo = yield photos.fetch (artist, request);
                if (photo != null && !request.is_cancelled ()) texture = Gdk.Texture.from_bytes (photo.bytes);
            } catch (Error e) { }
            if (!closed && !request.is_cancelled ()) {
                if (photo != null && texture != null) {
                    remember_photo (artist, photo);
                    foreach (var row in artist_rows)
                        if (row.get_mapped () && row.artist_group?.artist == artist) row.show_portrait (texture, photo);
                } else {
                    remember_unavailable_thumbnail (artist);
                }
            }
            thumbnail_cancel = null;
            schedule_thumbnails ();
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
            now_cover.set_size_request (48, 48);
            now_cover.add_css_class ("gtkplayer-artwork");
            now_cover.overflow = Gtk.Overflow.HIDDEN;
            now_cover.valign = Gtk.Align.CENTER;
            now_cover.pixel_size = 22;
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
                set_library_summary (empty_title, empty_hint);
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
                        set_library_summary (empty_title, empty_hint);
                    }
                }
            } catch (Error e) {
                if (!closed) {
                    if (watched_uri != null) enable_fallback ();
                    if (library.length == 0) {
                        empty_title = "No se pudo cargar la biblioteca";
                        empty_hint = "Revisá la ubicación en Preferencias y volvé a cargar";
                        set_library_summary (empty_title, empty_hint);
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
                if (track != null) {
                    entry.track.cover_data = track.cover_data;
                    entry.track.codec = track.codec;
                    entry.track.sample_rate = track.sample_rate;
                    entry.track.bit_depth = track.bit_depth;
                    entry.track.channels = track.channels;
                    entry.track.bitrate = track.bitrate;
                    entry.track.audio_info_known = track.audio_info_known;
                }
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
                    track.number != previous.number || track.duration != previous.duration ||
                    track.audio_info_known != previous.audio_info_known || track.codec != previous.codec ||
                    track.sample_rate != previous.sample_rate || track.bit_depth != previous.bit_depth ||
                    track.channels != previous.channels || track.bitrate != previous.bitrate) return false;
                if (track.cover_data != previous.cover_data && (track.cover_data == null ||
                    previous.cover_data == null || track.cover_data.compare (previous.cover_data) != 0)) return false;
            }
            return true;
        }

        private static ListModel? sidebar_children (Object item) {
            var group = item as LibraryGroup;
            return group == null ? null : group.sidebar_children ();
        }

        private Gtk.ListView build_sidebar_list (Gtk.SingleSelection selection, bool artists) {
            var factory = new Gtk.SignalListItemFactory ();
            factory.setup.connect ((obj) => {
                var row = new LibrarySidebarRow ();
                if (artists) row.map.connect (schedule_thumbnails);
                var expander = new Gtk.TreeExpander ();
                expander.child = row;
                ((Gtk.ListItem) obj).child = expander;
            });
            factory.bind.connect ((obj) => {
                var item = (Gtk.ListItem) obj;
                var expander = (Gtk.TreeExpander) item.child;
                var branch = (Gtk.TreeListRow) item.item;
                expander.list_row = branch;
                var row = (LibrarySidebarRow) expander.child;
                var group = branch.item as LibraryGroup;
                if (group != null) row.bind_group (group, branch.depth == 0);
                else row.bind_track ((Track) branch.item);
                // GtkListItem gained an explicit accessible label in GTK 4.12.
                if (item.get_class ().find_property ("accessible-label") != null)
                    item.set ("accessible-label", row.tooltip_text);
                if (row.artist_group != null) {
                    artist_rows.append (row);
                    schedule_thumbnails ();
                }
            });
            factory.unbind.connect ((obj) => {
                var expander = (Gtk.TreeExpander) ((Gtk.ListItem) obj).child;
                var row = (LibrarySidebarRow) expander.child;
                if (row.artist_group != null) artist_rows.remove (row);
                row.unbind ();
                expander.list_row = null;
            });
            var list = new Gtk.ListView (selection, factory);
            list.name = artists ? "artist-list" : "sidebar-album-list";
            list.single_click_activate = true;
            list.add_css_class ("navigation-sidebar");
            list.add_css_class ("gtkplayer-browser-surface");
            list.update_property (Gtk.AccessibleProperty.LABEL, artists ? "Artistas de la biblioteca" : "Álbumes de la biblioteca", -1);
            return list;
        }

        private void activate_sidebar_row (Gtk.TreeListModel tree, uint position, string category) {
            var branch = tree.get_row (position);
            if (branch == null) return;
            var group = branch.item as LibraryGroup;
            if (group != null) {
                branch.expanded = !branch.expanded;
                browsing_page = category;
                if (group.albums != null) open_artist (group);
                else open_album (group);
                return;
            }
            var track = branch.item as Track;
            if (track != null) {
                var album = branch.get_parent ()?.item as LibraryGroup;
                if (album != null && (selected_artist != album.artist || selected_album != album.title)) {
                    browsing_page = category;
                    open_album (album, false);
                }
                var selection = category == "artists" ? sidebar_artist_selection : sidebar_album_selection;
                selection.selected = position;
                music_action ({track}, "now");
                navigation_overlay.show_sidebar = false;
            }
        }

        private static bool select_sidebar_item (Gtk.SingleSelection selection, Object item) {
            for (uint i = 0; i < selection.get_n_items (); i++) {
                var branch = (Gtk.TreeListRow) selection.get_item (i);
                if (branch.item != item) continue;
                selection.selected = i;
                return true;
            }
            return false;
        }

        private Gtk.SignalListItemFactory media_factory (string kind) {
            var factory = new Gtk.SignalListItemFactory ();
            factory.setup.connect ((obj) => {
                var item = (Gtk.ListItem) obj;
                var row = new MediaRow (kind == "album", kind == "queue");
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
                else row.bind_group ((LibraryGroup) item.item);
                update_row_status (row);
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

        private void go_back_in_library () {
            if (browsing_page == "artists" && selected_album != null && selected_artist != null) {
                var artist = find_sidebar_artist (selected_artist);
                if (artist != null) {
                    open_artist (artist);
                    return;
                }
            }
            set_library_page (sidebar_stack.visible_child_name ?? "albums");
        }

        private void set_library_page (owned string page) {
            browsing_page = page;
            var filtered = filtered_tracks ();
            selected_artist = selected_album = null;
            sidebar_album_selection.selected = Gtk.INVALID_LIST_POSITION;
            sidebar_artist_selection.selected = Gtk.INVALID_LIST_POSITION;
            library_back.visible = page == "songs";
            if (page == "songs") show_tracks (filtered, "Todas las pistas");
            else {
                visible_tracks = (owned) filtered;
                cover.visible = false;
                album_color = null;
                update_album_style ();
                album_grid_model.model = sidebar_album_store;
                browser_stack.visible_child_name = "albums";
                if (library.length == 0) set_library_summary (empty_title, empty_hint);
                else if (visible_tracks.length == 0) set_library_summary ("Sin resultados", "Probá con otro título, artista o álbum");
                else set_library_summary ("Álbumes", page == "artists" ? "Elegí un artista para ver sus álbumes" : "");
                update_player ();
            }
        }

        private Track[] filtered_tracks () {
            Track[] result = {};
            string query = search.text.casefold ().strip ();
            foreach (var track in library)
                if (query == "" || track.title.casefold ().contains (query) || track.artist.casefold ().contains (query) || track.album.casefold ().contains (query))
                    result += track;
            return result;
        }

        private LibraryGroup? find_sidebar_artist (string name) {
            for (uint i = 0; i < artist_store.get_n_items (); i++) {
                var artist = (LibraryGroup) artist_store.get_item (i);
                if (artist.artist == name) return artist;
            }
            return null;
        }

        private static string album_key (string artist, string album) {
            // Length-prefixed exact keys keep homonyms and Unicode spellings distinct.
            return "%u:%s%s".printf (artist.length, artist, album);
        }

        private static string branch_key (LibraryGroup group) {
            return group.albums != null ? "artist:" + group.artist : album_key (group.artist, group.title);
        }

        private static HashTable<string, bool> expanded_branches (Gtk.TreeListModel tree) {
            var expanded = new HashTable<string, bool> (str_hash, str_equal);
            for (uint i = 0; i < tree.get_n_items (); i++) {
                var branch = tree.get_row (i);
                if (branch.expanded && branch.item is LibraryGroup)
                    expanded.insert (branch_key ((LibraryGroup) branch.item), true);
            }
            return expanded;
        }

        private static void restore_expanded_branches (Gtk.TreeListModel tree, HashTable<string, bool> expanded) {
            if (expanded.size () == 0) return;
            // Expanding an artist exposes its albums later in the same traversal.
            for (uint i = 0; i < tree.get_n_items (); i++) {
                var branch = tree.get_row (i);
                if (branch.item is LibraryGroup && expanded.contains (branch_key ((LibraryGroup) branch.item)))
                    branch.expanded = true;
            }
        }

        private void rebuild_groups (bool preserve = false) {
            var albums = new HashTable<string, LibraryGroup> (str_hash, str_equal);
            var artists = new HashTable<string, LibraryGroup> (str_hash, str_equal);
            var ordered_albums = new List<LibraryGroup> ();
            var ordered_artists = new List<LibraryGroup> ();
            foreach (var track in filtered_tracks ()) {
                var artist = artists.lookup (track.artist);
                if (artist == null) {
                    artist = new LibraryGroup (track.artist, track.artist);
                    artists.insert (track.artist, artist);
                    ordered_artists.append (artist);
                }
                string id = album_key (track.artist, track.album);
                var album = albums.lookup (id);
                if (album == null) {
                    album = new LibraryGroup (track.album, track.artist);
                    albums.insert (id, album);
                    ordered_albums.append (album);
                    artist.add_album (album);
                }
                album.add (track);
                artist.add (track);
            }
            Object[] album_items = {};
            Object[] artist_items = {};
            foreach (var album in ordered_albums) album_items += album;
            foreach (var artist in ordered_artists) artist_items += artist;
            var expanded_albums = expanded_branches (sidebar_album_tree);
            var expanded_artists = expanded_branches (sidebar_artist_tree);
            sidebar_album_store.splice (0, sidebar_album_store.get_n_items (), album_items);
            artist_store.splice (0, artist_store.get_n_items (), artist_items);
            restore_expanded_branches (sidebar_album_tree, expanded_albums);
            restore_expanded_branches (sidebar_artist_tree, expanded_artists);
            if (preserve && selected_album != null) {
                var album = albums.lookup (album_key (selected_artist, selected_album));
                if (album != null) {
                    open_album (album, false);
                    return;
                }
            }
            if (preserve && browsing_page == "artists" && selected_artist != null) {
                var artist = artists.lookup (selected_artist);
                if (artist != null) { open_artist (artist); return; }
            }
            set_library_page (browsing_page);
        }

        private void open_album (LibraryGroup album, bool focus_play = true) {
            selected_artist = album.artist;
            selected_album = album.title;
            library_back.visible = true;
            if (browsing_page == "albums") {
                select_sidebar_item (sidebar_album_selection, album);
            } else if (!select_sidebar_item (sidebar_artist_selection, album)) {
                var artist = find_sidebar_artist (album.artist);
                if (artist != null) select_sidebar_item (sidebar_artist_selection, artist);
            }
            // Search locates an album; opening it always presents the complete record.
            Track[] complete = {};
            foreach (var track in library)
                if (track.artist == album.artist && track.album == album.title) complete += track;
            show_tracks (complete, album.title, true);
            if (focus_play) album_play.grab_focus ();
        }

        private void open_artist (LibraryGroup artist) {
            selected_artist = artist.artist;
            selected_album = null;
            visible_tracks = artist.tracks;
            library_back.visible = true;
            cover.visible = false;
            album_color = null;
            update_album_style ();
            select_sidebar_item (sidebar_artist_selection, artist);
            album_grid_model.model = artist.albums;
            set_library_summary (artist.title, track_count_text (artist.tracks.length));
            browser_stack.visible_child_name = "albums";
            update_player ();
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
            cover.visible = album_selected;
            album_color = null;
            if (album_selected) {
                cover.set_from_icon_name ("audio-x-generic-symbolic");
                cover.pixel_size = 40;
                foreach (var track in selection) {
                    if (track.cover_data == null) continue;
                    try {
                        var texture = Gdk.Texture.from_bytes (track.cover_data);
                        cover.set_from_paintable (texture);
                        cover.pixel_size = 144;
                        extract_album_color (texture);
                        break;
                    } catch (Error e) { }
                }
            }
            update_album_style ();
            visible_tracks = selection;
            track_store.remove_all ();
            browser_stack.visible_child_name = "songs";
            if (library.length == 0) set_library_summary (empty_title, empty_hint);
            else if (selection.length == 0) set_library_summary ("Sin resultados", "Probá con otro título, artista o álbum");
            else {
                string count = track_count_text (selection.length);
                uint64 duration = 0;
                foreach (var track in selection) duration += track.duration;
                string length = "%s min %02d s".printf ((duration / Gst.SECOND / 60).to_string (), (int) (duration / Gst.SECOND % 60));
                set_library_summary (title, album_selected ? selection[0].artist + " · " + count + " · " + length : count);
            }
            foreach (var track in selection) track_store.append (track);
            update_player ();
        }
        private void set_library_summary (string title, string subtitle = "") {
            bool album = selected_album != null;
            var menu_parent = (Gtk.Box) selection_menu.get_parent ();
            var menu_target = album ? album_actions : album_summary;
            if (menu_parent != menu_target) {
                menu_parent.remove (selection_menu);
                menu_target.append (selection_menu);
            }
            search.visible = !album;
            selection_kind.visible = album;
            album_actions.visible = album;
            selection_format.visible = album && visible_tracks.length > 0;
            if (selection_format.visible) {
                string description = visible_tracks[0].audio_description ();
                foreach (var track in visible_tracks) {
                    if (track.audio_description () == description) continue;
                    description = "Formatos de audio variados · Detalles en cada pista";
                    break;
                }
                selection_format.label = description;
            }
            heading.label = title;
            heading.tooltip_text = title;
            selection_hint.label = subtitle;
            selection_hint.tooltip_text = subtitle == "" ? null : subtitle;
            selection_hint.visible = subtitle != "";
            selection_menu.visible = visible_tracks.length > 0;
            show_all_tracks.visible = browsing_page != "songs";
            bool searching = search.text.strip () != "";
            show_all_tracks.label = searching ? "Ver pistas de la búsqueda" : "Ver todas las pistas";
            if (selection_menu.visible) {
                string scope = selected_album != null ? "Acciones del álbum" :
                    selected_artist != null ? "Acciones del artista" :
                    searching ? "Acciones de los resultados" : "Acciones de la biblioteca";
                selection_menu.tooltip_text = scope;
                selection_menu.update_property (Gtk.AccessibleProperty.LABEL, scope, -1);
            }
        }

        private static string track_count_text (uint count) {
            return (count == 1 ? "%u pista" : "%u pistas").printf (count);
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
            tint.alpha = theme.dark ? 0.22f : 0.14f;
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
            queue_count.visible = queue.entries.length > 0;
            queue_count.label = track_count_text (queue.entries.length);
            clear_button.sensitive = queue.entries.length > (queue.current == null ? 0 : 1);
            undo_button.sensitive = queue.can_undo;
        }
        private void update_player () {
            if (closed) return;
            update_visible_status (tracks);
            update_visible_status (queue_list);
            bool album_playing = current_in_album () && player.state == Gst.State.PLAYING;
            album_play.icon_name = album_playing ? "media-playback-pause-symbolic" : "media-playback-start-symbolic";
            string album_action = album_playing ? "Pausar álbum" : current_in_album () ? "Continuar álbum" : "Reproducir álbum";
            album_play.tooltip_text = album_action;
            album_play.update_property (Gtk.AccessibleProperty.LABEL, album_action, -1);
            album_play.sensitive = album_append.sensitive = album_next.sensitive = visible_tracks.length > 0;
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
                now_playing.tooltip_text = null;
                now_cover.set_from_icon_name ("audio-x-generic-symbolic");
                now_cover.pixel_size = 22;
                now_cover_uri = null;
                return;
            }
            if (now_cover_uri != track.uri || now_cover_data != track.cover_data) {
                now_cover.set_from_icon_name ("audio-x-generic-symbolic");
                now_cover.pixel_size = 22;
                now_cover_uri = track.uri;
                now_cover_data = track.cover_data;
                if (track.cover_data != null) {
                    try {
                        now_cover.set_from_paintable (Gdk.Texture.from_bytes (track.cover_data));
                        now_cover.pixel_size = 48;
                    }
                    catch (Error e) { }
                }
            }
            now_playing.label = track.title + "\n" + track.artist;
            now_playing.tooltip_text = track.title + " — " + track.artist + "\n" + track.audio_description ();

        }
        private bool current_in_album () {
            if (selected_album == null || queue.current == null) return false;
            foreach (var track in visible_tracks)
                if (track.uri == queue.current.uri) return true;
            return false;
        }
        private void update_row_status (MediaRow row) {
            bool current = row.entry_id != null ? queue.current_entry?.id == row.entry_id :
                row.song_row && row.tracks.length > 0 && row.tracks[0].uri == queue.current?.uri;
            string status = "";
            if (current) status = player.state == Gst.State.PLAYING ? "Reproduciendo" :
                player.state == Gst.State.PAUSED ? "En pausa" : "Actual";
            else if (row.entry_id != null) status = queue.find (row.entry_id) < queue.index ? "Anterior" : "Pendiente";
            row.set_status (status, current);
        }
        private void update_visible_status (Gtk.Widget widget) {
            if (widget is MediaRow) { update_row_status ((MediaRow) widget); return; }
            for (var child = widget.get_first_child (); child != null; child = child.get_next_sibling ())
                update_visible_status (child);
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
