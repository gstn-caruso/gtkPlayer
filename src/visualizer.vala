namespace Music {
    public class VisualizerWindow : Adw.Window {
        private Player player;
        private Gtk.GLArea area;
        private VisualizerRenderer? renderer;
        private Adw.ToolbarView toolbar;
        private Gtk.Revealer controls;
        private Gtk.Button fullscreen_button;
        private Gtk.Button expand;
        private Gtk.Button[] preset_buttons = {};
        private Adw.WindowTitle window_title;
        private Adw.StatusPage placeholder;
        private Gtk.Stack stack;
        private uint tick;
        private uint hide_controls;
        private ulong player_changed;
        private bool closed;
        private bool failed;
        private bool loaded;
        public uint rendered_frames { get; private set; }
        public uint preset_switches { get { return renderer != null ? renderer.get_switches () : 0; } }
        internal uint active_preset { get { return renderer != null ? renderer.get_preset () : 0; } }

        public VisualizerWindow (Window owner, Player player) {
            Object (title: "Visualizador", transient_for: owner, destroy_with_parent: true,
                application: owner.application, default_width: 900, default_height: 600);
            this.player = player;
            name = "visualizer-window";
            toolbar = new Adw.ToolbarView ();
            var header = new Adw.HeaderBar ();
            window_title = new Adw.WindowTitle ("Visualizador", "Efectos aleatorios · projectM");
            header.title_widget = window_title;
            header.pack_start (preset_button (-1, "visualizer-previous-preset"));
            header.pack_start (preset_button (1, "visualizer-next-preset"));
            expand = button ("view-fullscreen-symbolic", "Pantalla completa (F11)", "visualizer-fullscreen");
            expand.clicked.connect (toggle_fullscreen);
            header.pack_end (expand);
            toolbar.add_top_bar (header);
            var overlay = new Gtk.Overlay ();
            stack = new Gtk.Stack ();
            area = new Gtk.GLArea () { hexpand = true, vexpand = true, auto_render = false, focusable = true };
            area.name = "visualizer-surface";
            area.set_required_version (3, 3);
            area.set_use_es (false);
            area.update_property (Gtk.AccessibleProperty.LABEL, "Visualización de la música", -1);
            area.realize.connect (() => {
                area.make_current ();
                if (area.get_error () != null) { fail (); return; }
                renderer = new VisualizerRenderer ();
                if (renderer == null) fail ();
                update_preset_controls ();
            });
            area.unrealize.connect (() => {
                area.make_current ();
                renderer = null;
                update_preset_controls ();
            });
            area.render.connect (() => {
                if (renderer == null || failed) return true;
                var pcm = player.state == Gst.State.PLAYING ? player.visualization.read () : new uint8[0];
                int scale = area.scale_factor;
                if (!renderer.render (pcm, area.get_width () * scale, area.get_height () * scale)) fail ();
                else rendered_frames++;
                return true;
            });
            stack.add_named (area, "visualization");
            placeholder = new Adw.StatusPage () {
                icon_name = "audio-x-generic-symbolic", title = "Poné música para empezar",
                description = "Reproducí una canción desde la biblioteca o la cola. Los efectos cambian solos y reaccionan al audio."
            };
            stack.add_named (placeholder, "status");
            overlay.child = stack;
            controls = new Gtk.Revealer () { halign = Gtk.Align.CENTER, valign = Gtk.Align.END,
                margin_bottom = 24, margin_start = 12, margin_end = 12 };
            var buttons = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
            buttons.add_css_class ("osd");
            buttons.add_css_class ("toolbar");
            buttons.append (preset_button (-1, "visualizer-previous-preset-fullscreen"));
            buttons.append (preset_button (1, "visualizer-next-preset-fullscreen"));
            fullscreen_button = button ("view-restore-symbolic", "Salir de pantalla completa (Esc)", "visualizer-unfullscreen");
            fullscreen_button.clicked.connect (() => { unfullscreen (); });
            buttons.append (fullscreen_button);
            var close_button = button ("window-close-symbolic", "Cerrar visualizador", "visualizer-close");
            close_button.clicked.connect (() => { close (); });
            buttons.append (close_button);
            controls.child = buttons;
            overlay.add_overlay (controls);
            toolbar.content = overlay;
            content = toolbar;

            var motion = new Gtk.EventControllerMotion ();
            motion.motion.connect (() => { reveal_controls (); });
            ((Gtk.Widget) this).add_controller (motion);
            var touch = new Gtk.GestureClick ();
            touch.released.connect (() => { reveal_controls (); });
            overlay.add_controller (touch);
            var keys = new Gtk.EventControllerKey ();
            keys.name = "visualizer-keys";
            keys.propagation_phase = Gtk.PropagationPhase.CAPTURE;
            keys.key_pressed.connect ((key, code, modifiers) => {
                if (key == Gdk.Key.F11) { toggle_fullscreen (); return true; }
                if (key == Gdk.Key.Escape && fullscreened) { unfullscreen (); return true; }
                if ((modifiers & Gdk.ModifierType.CONTROL_MASK) != 0 && key == Gdk.Key.w) { close (); return true; }
                if (fullscreened) reveal_controls ();
                return false;
            });
            ((Gtk.Widget) this).add_controller (keys);
            notify["fullscreened"].connect (() => {
                toolbar.reveal_top_bars = !fullscreened;
                if (fullscreened) {
                    reveal_controls ();
                    if (area.get_mapped ()) area.grab_focus ();
                    else fullscreen_button.grab_focus ();
                } else {
                    controls.reveal_child = false;
                    cancel_hide ();
                    expand.grab_focus ();
                }
            });
            player_changed = player.changed.connect (update_state);
            map.connect (() => { update_state (); });
            unmap.connect (() => { stop_tick (); player.visualization.enable (false); });
            close_request.connect (() => {
                shutdown ();
                return false;
            });
            update_state ();
        }

        private static Gtk.Button button (string icon, string label, string name) {
            var result = new Gtk.Button.from_icon_name (icon) { tooltip_text = label, name = name };
            result.update_property (Gtk.AccessibleProperty.LABEL, label, -1);
            return result;
        }
        private Gtk.Button preset_button (int direction, string name) {
            var result = button (direction < 0 ? "go-previous-symbolic" : "go-next-symbolic",
                direction < 0 ? "Preset anterior" : "Preset siguiente", name);
            result.sensitive = false;
            result.clicked.connect (() => {
                if (renderer == null || failed || !loaded) return;
                renderer.step (direction, player.state == Gst.State.PLAYING);
                area.queue_render ();
            });
            preset_buttons += result;
            return result;
        }
        private void update_preset_controls () {
            foreach (var control in preset_buttons)
                control.sensitive = renderer != null && !failed && loaded && player.state >= Gst.State.PAUSED;
        }
        private void toggle_fullscreen () {
            if (fullscreened) unfullscreen (); else fullscreen ();
        }
        private void reveal_controls () {
            if (!fullscreened) return;
            cancel_hide ();
            controls.reveal_child = true;
            hide_controls = Timeout.add_seconds (3, () => {
                hide_controls = 0;
                // Keyboard users keep their focused controls available.
                var focused = get_focus ();
                if (focused == null || !focused.is_ancestor (controls)) controls.reveal_child = false;
                return Source.REMOVE;
            });
        }
        private void cancel_hide () {
            if (hide_controls != 0) { Source.remove (hide_controls); hide_controls = 0; }
        }
        private void fail () {
            failed = true;
            update_preset_controls ();
            placeholder.title = "No se pudo iniciar el visualizador";
            placeholder.description = "Comprobá que el sistema admita OpenGL 3.3. Podés seguir escuchando música.";
            stack.visible_child_name = "status";
            player.visualization.enable (false);
            stop_tick ();
        }
        private void update_state () {
            if (closed || failed) return;
            if (!player.visualization.available) { fail (); return; }
            bool playing = player.state == Gst.State.PLAYING;
            bool paused = player.state == Gst.State.PAUSED;
            if (player.state == Gst.State.NULL) loaded = false;
            stack.visible_child_name = playing || (paused && loaded) ? "visualization" : "status";
            window_title.subtitle = paused ? "En pausa" : "Efectos aleatorios · projectM";
            if (playing) loaded = true;
            update_preset_controls ();
            player.visualization.enable (playing && get_mapped ());
            if (!playing || !get_mapped ()) { stop_tick (); return; }
            if (tick == 0) tick = Timeout.add (33, () => {
                area.queue_render ();
                return Source.CONTINUE;
            });
        }
        private void stop_tick () {
            if (tick != 0) { Source.remove (tick); tick = 0; }
        }
        private void shutdown () {
            if (closed) return;
            closed = true;
            stop_tick ();
            cancel_hide ();
            player.visualization.enable (false);
            player.disconnect (player_changed);
        }
    }
}
