Gtk.Widget? find_named (Gtk.Widget widget, string name) {
    if (widget.name == name) return widget;
    for (var child = widget.get_first_child (); child != null; child = child.get_next_sibling ()) {
        var found = find_named (child, name);
        if (found != null) return found;
    }
    return null;
}

delegate bool Condition ();
void wait_until (Condition condition) {
    int64 deadline = get_monotonic_time () + 10 * TimeSpan.SECOND;
    while (!condition () && get_monotonic_time () < deadline) {
        while (MainContext.default ().pending ()) MainContext.default ().iteration (false);
        Thread.usleep (1000);
    }
    assert (condition ());
}

string fixture (string duration = "0.2") {
    try {
        string folder = DirUtils.make_tmp ("gtkplayer-ui-XXXXXX");
        string[] command = {"ffmpeg", "-v", "error", "-f", "lavfi", "-i", "sine=duration=" + duration, "-y", folder + "/song.wav"};
        int status;
        Process.spawn_sync (null, command, null, SpawnFlags.SEARCH_PATH, null, null, null, out status);
        assert (status == 0);
        // Prepare BEFORE Window construction: autoload must never reach the NAS.
        new Music.LocationSettings (folder + "/settings.ini").save (folder);
        return folder;
    } catch (Error e) { error ("%s", e.message); }
}

void remove_fixture (string folder) {
    FileUtils.unlink (folder + "/song.wav");
    FileUtils.unlink (folder + "/settings.ini");
    DirUtils.remove (folder);
}

int application_serial = 0;
Adw.Application application () {
    var app = new Adw.Application ("io.github.gtkplayer.Test%d".printf (++application_serial), ApplicationFlags.NON_UNIQUE);
    try { app.register (); } catch (Error e) { error ("%s", e.message); }
    return app;
}

Gtk.Window open_preferences (Music.Window window) {
    ((Gtk.Button) find_named (window, "open-preferences")).clicked ();
    var toplevels = Gtk.Window.get_toplevels ();
    for (uint i = 0; i < toplevels.get_n_items (); i++) {
        var candidate = toplevels.get_item (i) as Gtk.Window;
        if (candidate.transient_for == window) return candidate;
    }
    error ("Preferences window not found");
}

bool has_text (Gtk.Widget widget, string text) {
    if (widget is Gtk.Label && ((Gtk.Label) widget).label.contains (text)) return true;
    for (var child = widget.get_first_child (); child != null; child = child.get_next_sibling ())
        if (has_text (child, text)) return true;
    return false;
}

Gtk.Button? find_play (Gtk.Widget widget) {
    if (widget is Gtk.Button && widget.tooltip_text == "Reproducir o pausar") return (Gtk.Button) widget;
    for (var child = widget.get_first_child (); child != null; child = child.get_next_sibling ()) {
        var found = find_play (child);
        if (found != null) return found;
    }
    return null;
}

Gtk.ListBox? find_list (Gtk.Widget widget) {
    if (widget is Gtk.ListBox) return (Gtk.ListBox) widget;
    for (var child = widget.get_first_child (); child != null; child = child.get_next_sibling ()) {
        var found = find_list (child);
        if (found != null) return found;
    }
    return null;
}

Gtk.Widget? find_toast (Gtk.Widget widget) {
    if (widget.get_css_name () == "toast") return widget;
    for (var child = widget.get_first_child (); child != null; child = child.get_next_sibling ()) {
        var found = find_toast (child);
        if (found != null) return found;
    }
    return null;
}

Gtk.Widget wait_for_notice (Music.Window window, string message) {
    assert (find_named (window, "library-notices") is Adw.ToastOverlay);
    wait_until (() => {
        var toast = find_toast (window);
        return toast != null && toast.get_mapped () && has_text (toast, message);
    });
    return find_toast (window);
}

bool contains_entry (Gtk.Widget widget) {
    if (widget is Gtk.Entry) return true;
    for (var child = widget.get_first_child (); child != null; child = child.get_next_sibling ())
        if (contains_entry (child)) return true;
    return false;
}

void wait_for_layout (Gtk.Widget widget) {
    int frames = 0;
    widget.add_tick_callback (() => { return ++frames < 3; });
    wait_until (() => { return frames >= 3 && widget.get_width () > 0; });
}

Graphene.Rect bounds_in (Gtk.Widget widget, Gtk.Widget parent) {
    Graphene.Rect bounds;
    assert (widget.compute_bounds (parent, out bounds));
    return bounds;
}

void capture_if_requested (Gtk.Widget widget, string suffix = "") {
    string? path = Environment.get_variable ("GTKPLAYER_TEST_CAPTURE");
    if (path == null) return;
    if (suffix != "") path = path + suffix + ".png";
    wait_for_layout (widget);
    var paintable = new Gtk.WidgetPaintable (widget);
    var snapshot = new Gtk.Snapshot ();
    paintable.snapshot (snapshot, widget.get_width (), widget.get_height ());
    var node = snapshot.free_to_node ();
    assert (node != null);
    var texture = widget.get_native ().get_renderer ().render_texture (node, null);
    assert (texture.save_to_png (path));
    Test.message ("Fixture capture: %s", path);
}

int main (string[] args) {
    Test.init (ref args);
    Gst.init (ref args);
    Adw.init ();
    string? scheme = Environment.get_variable ("GTKPLAYER_TEST_COLOR_SCHEME");
    if (scheme != null) {
        assert (scheme == "light" || scheme == "dark");
        Adw.StyleManager.get_default ().color_scheme = scheme == "dark"
            ? Adw.ColorScheme.FORCE_DARK : Adw.ColorScheme.FORCE_LIGHT;
    }
    // Replaces the old explicit-load contract, retaining activation, layout,
    // local audio discovery and remembered-location regression assertions.
    Test.add_func ("/ui/startup-local-library-four-zones", () => {
        string folder = fixture ();
        string config = folder + "/settings.ini";
        var app = application ();
        Music.Window? window = null;
        app.activate.connect (() => {
            window = new Music.Window (app, config, Gst.ElementFactory.make ("fakesink", null));
            window.present ();
        });
        app.activate ();
        assert (window.visible);
        foreach (string zone in new string[] {"library", "tracks", "details", "controls"})
            assert (find_named (window, zone) != null);
        foreach (string control in new string[] {"location", "load", "apply", "cancel", "browse", "reload"})
            assert (find_named (window, control) == null);
        assert (!contains_entry (window));
        assert (find_named (window, "open-preferences") != null);
        wait_until (() => { return !window.loading && window.track_count == 1; });
        assert (new Music.LocationSettings (config).load () == File.new_for_path (folder).get_uri ());
        assert (has_text (find_named (window, "tracks"), "song"));
        assert (has_text (find_named (window, "controls"), "Nada en reproducción"));
        window.close ();
        var reopened = new Music.Window (app, config, Gst.ElementFactory.make ("fakesink", null));
        reopened.present ();
        wait_until (() => { return !reopened.loading && reopened.track_count == 1; });
        reopened.close ();
        remove_fixture (folder);
    });
    Test.add_func ("/ui/single-activation-specific-track-and-queue", () => {
        string folder = fixture ("8");
        try {
            File.new_for_path (folder + "/song.wav").copy (File.new_for_path (folder + "/track-two.wav"), FileCopyFlags.NONE);
        } catch (Error e) { error ("%s", e.message); }
        var sink = Gst.ElementFactory.make ("fakesink", null);
        sink.set ("sync", true);
        var window = new Music.Window (application (), folder + "/settings.ini", sink);
        window.present ();
        wait_until (() => { return !window.loading && window.track_count == 2; });
        var tracks = find_list (find_named (window, "tracks"));
        var queue = find_list (find_named (window, "details"));
        var title = (Gtk.Label) find_named (window, "now-playing");
        var play = find_play (window);
        assert (tracks.activate_on_single_click);
        assert (queue.activate_on_single_click);
        assert (!has_text (window, "Doble clic"));
        // Native row activation is also the keyboard path; this is not a physical pointer test.
        var second = tracks.get_row_at_index (1);
        tracks.select_row (second);
        assert (((Gtk.Widget) second).activate ());
        wait_until (() => { return title.label.has_prefix ("track-two\n") && play.icon_name == "media-playback-pause-symbolic"; });
        assert (tracks.get_selected_row () == second);
        assert (queue.get_selected_row ().get_index () == 1);
        assert (queue.get_row_at_index (2) == null);
        assert (has_text (find_named (window, "details"), "track-two"));
        var first = queue.get_row_at_index (0);
        queue.select_row (first);
        assert (((Gtk.Widget) first).activate ());
        wait_until (() => { return title.label.has_prefix ("song\n") && play.icon_name == "media-playback-pause-symbolic"; });
        assert (queue.get_selected_row () == first);
        window.close ();
        FileUtils.unlink (folder + "/track-two.wav");
        remove_fixture (folder);
    });
    Test.add_func ("/ui/transport-empty-and-load-transitions", () => {
        string empty = fixture ();
        string populated = fixture ();
        assert (FileUtils.unlink (empty + "/song.wav") == 0);
        var window = new Music.Window (application (), empty + "/settings.ini", Gst.ElementFactory.make ("fakesink", null));
        window.present ();
        wait_until (() => { return !window.loading; });
        var bar = find_named (window, "controls");
        var play = find_play (bar);
        var previous = (Gtk.Button) play.get_parent ().get_first_child ();
        var next = (Gtk.Button) play.get_parent ().get_last_child ();
        var volume = (Gtk.Scale) find_named (bar, "volume");
        assert (!previous.sensitive && !play.sensitive && !next.sensitive);
        assert (volume.sensitive);
        assert (bar.child_focus (Gtk.DirectionType.TAB_FORWARD));
        assert (window.get_focus () == volume);
        double old_volume = volume.get_value ();
        volume.move_slider (Gtk.ScrollType.STEP_LEFT);
        assert (volume.get_value () < old_volume);
        window.load_library.begin (populated);
        wait_until (() => { return !window.loading && window.track_count == 1; });
        assert (!previous.sensitive && play.sensitive && !next.sensitive);
        window.load_library.begin (empty);
        wait_until (() => { return !window.loading && window.track_count == 0; });
        assert (!previous.sensitive && !play.sensitive && !next.sensitive);
        window.close ();
        remove_fixture (empty);
        remove_fixture (populated);
    });
    Test.add_func ("/ui/empty-library-queue-and-load-failure-guidance", () => {
        string folder = fixture ();
        assert (FileUtils.unlink (folder + "/song.wav") == 0);
        var window = new Music.Window (application (), folder + "/settings.ini", Gst.ElementFactory.make ("fakesink", null));
        window.present ();
        wait_until (() => { return !window.loading; });
        var center = find_named (window, "tracks");
        assert (has_text (center, "Biblioteca vacía"));
        assert (has_text (center, "Elegí una ubicación con música en Preferencias"));
        assert (!has_text (center, "Seleccioná un álbum"));
        var preferences = open_preferences (window);
        assert (has_text (preferences, "0 pistas cargadas · 0 archivos de audio omitidos"));
        preferences.close ();
        var stack = (Gtk.Stack) find_list (find_named (window, "details")).get_ancestor (typeof (Gtk.Stack));
        stack.visible_child_name = "queue";
        wait_for_layout (stack);
        var placeholder = find_named (window, "queue-empty");
        assert (placeholder is Adw.StatusPage && placeholder.get_mapped ());
        assert (has_text (placeholder, "Cola vacía"));
        assert (has_text (placeholder, "Cargá música desde Preferencias"));
        window.load_library.begin (folder + "/unavailable");
        wait_until (() => { return !window.loading; });
        assert (has_text (center, "No se pudo cargar la biblioteca"));
        assert (has_text (center, "Revisá la ubicación en Preferencias y volvé a cargar"));
        assert (!has_text (center, "Biblioteca vacía"));
        wait_for_notice (window, "No se pudo cargar la biblioteca. Revisá Preferencias.");
        preferences = open_preferences (window);
        assert (((Gtk.Label) find_named (preferences, "preferences-status")).label.contains ("unavailable"));
        preferences.close ();
        window.load_library.begin (folder);
        wait_until (() => { return !window.loading; });
        assert (has_text (center, "Biblioteca vacía"));
        assert (!has_text (center, "No se pudo cargar"));
        window.close ();
        remove_fixture (folder);
    });
    Test.add_func ("/ui/current-track-survives-group-and-location-changes", () => {
        string folder = fixture ("8");
        string empty = fixture ();
        assert (FileUtils.unlink (empty + "/song.wav") == 0);
        try {
            string[] command = {"ffmpeg", "-v", "error", "-i", folder + "/song.wav", "-metadata", "album=Otro álbum", folder + "/other.flac"};
            int status;
            Process.spawn_sync (null, command, null, SpawnFlags.SEARCH_PATH, null, null, null, out status);
            assert (status == 0);
        } catch (Error e) { error ("%s", e.message); }
        var sink = Gst.ElementFactory.make ("fakesink", null);
        sink.set ("sync", true);
        var window = new Music.Window (application (), folder + "/settings.ini", sink);
        window.present ();
        wait_until (() => { return !window.loading && window.track_count == 2; });
        var groups = find_list (find_named (window, "library"));
        var tracks = find_list (find_named (window, "tracks"));
        var play = find_play (window);
        var previous = (Gtk.Button) play.get_parent ().get_first_child ();
        var next = (Gtk.Button) play.get_parent ().get_last_child ();
        // Filter to the original WAV's album, leaving one playable visible track.
        Gtk.ListBoxRow? album = null;
        for (int i = 1; groups.get_row_at_index (i) != null; i++)
            if (has_text (groups.get_row_at_index (i), "Sin álbum")) album = groups.get_row_at_index (i);
        assert (album != null);
        groups.select_row (album);
        assert (tracks.get_row_at_index (1) == null);
        assert (has_text (find_named (window, "tracks"), "Sin álbum — Artista desconocido · 1 pista"));
        assert (play.sensitive && !previous.sensitive && !next.sensitive);
        assert (((Gtk.Widget) tracks.get_row_at_index (0)).activate ());
        wait_until (() => { return play.icon_name == "media-playback-pause-symbolic"; });
        groups.select_row (groups.get_row_at_index (0));
        assert (tracks.get_row_at_index (1) != null);
        // The active queue is still the single-track selection, not the newly visible group.
        assert (play.sensitive && !previous.sensitive && !next.sensitive);
        window.load_library.begin (empty);
        wait_until (() => { return !window.loading && window.track_count == 0; });
        assert (tracks.get_row_at_index (0) == null);
        assert (play.sensitive && !previous.sensitive && !next.sensitive);
        assert (has_text (find_named (window, "controls"), "song\n"));
        play.clicked ();
        wait_until (() => { return play.icon_name == "media-playback-start-symbolic"; });
        assert (play.sensitive);
        play.clicked ();
        wait_until (() => { return play.icon_name == "media-playback-pause-symbolic"; });
        assert (has_text (find_named (window, "controls"), "song\n"));
        window.close ();
        FileUtils.unlink (folder + "/other.flac");
        remove_fixture (folder);
        remove_fixture (empty);
    });
    Test.add_func ("/ui/transport-eos-queue-boundaries", () => {
        string folder = fixture ("0.5");
        try {
            File.new_for_path (folder + "/song.wav").copy (File.new_for_path (folder + "/track-two.wav"), FileCopyFlags.NONE);
        } catch (Error e) { error ("%s", e.message); }
        var sink = Gst.ElementFactory.make ("fakesink", null);
        sink.set ("sync", true);
        var window = new Music.Window (application (), folder + "/settings.ini", sink);
        window.present ();
        wait_until (() => { return !window.loading && window.track_count == 2; });
        var play = find_play (window);
        var previous = (Gtk.Button) play.get_parent ().get_first_child ();
        var next = (Gtk.Button) play.get_parent ().get_last_child ();
        var title = (Gtk.Label) find_named (window, "now-playing");
        play.clicked ();
        wait_until (() => { return play.icon_name == "media-playback-pause-symbolic"; });
        assert (title.label.has_prefix ("song\n"));
        assert (!previous.sensitive && play.sensitive && next.sensitive);
        wait_until (() => { return title.label.has_prefix ("track-two\n"); });
        assert (previous.sensitive && play.sensitive && !next.sensitive);
        var preferences = open_preferences (window);
        wait_until (() => { return has_text (preferences, "Fin de la cola"); });
        assert (play.icon_name == "media-playback-start-symbolic");
        assert (previous.sensitive && play.sensitive && !next.sensitive);
        assert (find_list (find_named (window, "details")).get_selected_row ().get_index () == 1);
        window.close ();
        FileUtils.unlink (folder + "/track-two.wav");
        remove_fixture (folder);
    });
    Test.add_func ("/ui/plural-library-and-selection-summary", () => {
        string folder = fixture ();
        try {
            File.new_for_path (folder + "/song.wav").copy (File.new_for_path (folder + "/other.wav"), FileCopyFlags.NONE);
            FileUtils.set_contents (folder + "/broken.wav", "not audio");
            FileUtils.set_contents (folder + "/broken-two.wav", "not audio");
        } catch (Error e) { error ("%s", e.message); }
        var window = new Music.Window (application (), folder + "/settings.ini", Gst.ElementFactory.make ("fakesink", null));
        window.present ();
        wait_until (() => { return !window.loading && window.track_count == 2; });
        var preferences = open_preferences (window);
        assert (has_text (preferences, "2 pistas cargadas · 2 archivos de audio omitidos"));
        preferences.close ();
        assert (has_text (find_named (window, "tracks"), "Todas las pistas · 2 pistas"));
        var groups = find_list (find_named (window, "library"));
        groups.select_row (groups.get_row_at_index (1));
        assert (has_text (find_named (window, "tracks"), "Sin álbum — Artista desconocido · 2 pistas"));
        var stack = (Gtk.Stack) find_list (find_named (window, "details")).get_ancestor (typeof (Gtk.Stack));
        stack.visible_child_name = "queue";
        wait_for_layout (stack);
        var placeholder = find_named (window, "queue-empty");
        assert (placeholder.get_mapped ());
        assert (has_text (placeholder, "Activá una pista para reproducir la selección y crear la cola"));
        window.close ();
        foreach (string file in new string[] {"other.wav", "broken.wav", "broken-two.wav"}) FileUtils.unlink (folder + "/" + file);
        remove_fixture (folder);
    });
    Test.add_func ("/ui/no-status-row-summary-in-preferences", () => {
        string folder = fixture ();
        try { FileUtils.set_contents (folder + "/broken.wav", "not audio"); }
        catch (Error e) { error ("%s", e.message); }
        var window = new Music.Window (application (), folder + "/settings.ini", Gst.ElementFactory.make ("fakesink", null));
        window.present ();
        wait_until (() => { return !window.loading && window.track_count == 1; });
        var preferences = open_preferences (window);
        // Correct the old fixed-plural contract: singular counts must agree in Spanish.
        assert (has_text (preferences, "1 pista cargada · 1 archivo de audio omitido"));
        preferences.close ();
        wait_for_layout (window);
        var header = window.content.get_first_child ();
        assert (header is Adw.HeaderBar);
        var panels = find_named (window, "library").get_ancestor (typeof (Gtk.Paned));
        var h = bounds_in (header, window);
        var p = bounds_in (panels, window);
        float gap = p.get_y () - h.get_y () - h.get_height ();
        Test.message ("Header bottom=%.0f, panels top=%.0f, gap=%.0f", h.get_y () + h.get_height (), p.get_y (), gap);
        assert (gap.abs () <= 1);
        assert (find_named (window, "library-status") == null);
        assert (!has_text (window, "pistas cargadas"));
        assert (!has_text (window, "pista cargada"));
        assert (!has_text (window, "audio omitidos"));
        assert (has_text (find_named (window, "tracks"), "Todas las pistas · 1 pista"));
        assert (!has_text (find_named (window, "tracks"), "1 pistas"));
        capture_if_requested (window);
        window.close ();
        FileUtils.unlink (folder + "/broken.wav");
        remove_fixture (folder);
    });
    Test.add_func ("/ui/preferences-apply-and-reopen", () => {
        string first = fixture ();
        string second = fixture ();
        string config = first + "/settings.ini";
        try {
            File.new_for_path (second + "/song.wav").copy (File.new_for_path (second + "/other.wav"), FileCopyFlags.NONE);
        } catch (Error e) { error ("%s", e.message); }
        var app = application ();
        var window = new Music.Window (app, config, Gst.ElementFactory.make ("fakesink", null));
        window.present ();
        wait_until (() => { return !window.loading && window.track_count == 1; });
        var preferences = open_preferences (window);
        assert (open_preferences (window) == preferences);
        var entry = (Gtk.Entry) find_named (preferences, "location");
        var apply = (Gtk.Button) find_named (preferences, "apply");
        entry.text = second;
        apply.clicked ();
        // Applying persists the choice even before discovery completes.
        assert (new Music.LocationSettings (config).load () == File.new_for_path (second).get_uri ());
        assert (window.loading);
        assert (!apply.sensitive);
        assert (!find_named (preferences, "reload").sensitive);
        wait_until (() => { return !window.loading && window.track_count == 2; });
        assert (apply.sensitive);
        assert (has_text (find_named (window, "tracks"), "other"));
        ((Gtk.Button) find_named (preferences, "reload")).clicked ();
        assert (window.loading);
        wait_until (() => { return !window.loading; });
        assert (window.track_count == 2);
        window.close ();
        var reopened = new Music.Window (app, config, Gst.ElementFactory.make ("fakesink", null));
        reopened.present ();
        wait_until (() => { return !reopened.loading && reopened.track_count == 2; });
        assert (has_text (find_named (reopened, "tracks"), "other"));
        reopened.close ();
        FileUtils.unlink (second + "/other.wav");
        remove_fixture (first);
        remove_fixture (second);
    });
    Test.add_func ("/ui/preferences-reject-and-discard", () => {
        string folder = fixture ();
        string config = folder + "/settings.ini";
        string original = new Music.LocationSettings (config).load ();
        var window = new Music.Window (application (), config, Gst.ElementFactory.make ("fakesink", null));
        window.present ();
        wait_until (() => { return !window.loading && window.track_count == 1; });
        var preferences = open_preferences (window);
        var entry = (Gtk.Entry) find_named (preferences, "location");
        entry.text = folder + "/not-applied";
        preferences.close ();
        assert (new Music.LocationSettings (config).load () == original);
        assert (open_preferences (window) == preferences);
        assert (entry.text == original);
        foreach (string invalid in new string[] {"", "https://example.invalid/music", "smb://userinfo@example.invalid/music"}) {
            entry.text = invalid;
            ((Gtk.Button) find_named (preferences, "apply")).clicked ();
            assert (!window.loading);
            assert (window.track_count == 1);
            assert (new Music.LocationSettings (config).load () == original);
            assert (((Gtk.Label) find_named (preferences, "preferences-status")).label != "");
            assert (find_named (preferences, "apply").sensitive);
            assert (find_named (preferences, "reload").sensitive);
        }
        assert (has_text (find_named (window, "tracks"), "song"));
        window.close ();
        remove_fixture (folder);
    });
    Test.add_func ("/ui/unavailable-location-and-recovery", () => {
        string folder = fixture ();
        string config = folder + "/settings.ini";
        string missing = folder + "/unavailable";
        try { new Music.LocationSettings (config).save (missing); }
        catch (Error e) { error ("%s", e.message); }
        var window = new Music.Window (application (), config, Gst.ElementFactory.make ("fakesink", null));
        window.present ();
        wait_until (() => { return !window.loading; });
        assert (window.track_count == 0);
        var notice = wait_for_notice (window, "No se pudo cargar la biblioteca. Revisá Preferencias.");
        assert (!has_text (notice, folder));
        assert (!has_text (notice, "file://"));
        var preferences = open_preferences (window);
        assert (((Gtk.Label) find_named (preferences, "preferences-status")).label.contains ("unavailable"));
        var entry = (Gtk.Entry) find_named (preferences, "location");
        var apply = (Gtk.Button) find_named (preferences, "apply");
        assert (apply.sensitive);
        entry.text = folder;
        apply.clicked ();
        wait_until (() => { return !window.loading && window.track_count == 1; });
        entry.text = missing;
        apply.clicked ();
        wait_until (() => { return !window.loading; });
        assert (window.track_count == 1);
        assert (has_text (find_named (window, "tracks"), "song"));
        assert (new Music.LocationSettings (config).load () == File.new_for_path (missing).get_uri ());
        foreach (string control in new string[] {"apply", "reload", "location", "browse"})
            assert (find_named (preferences, control).sensitive);
        assert (!find_named (preferences, "cancel").sensitive);
        notice = wait_for_notice (window, "No se pudo cargar la biblioteca. Revisá Preferencias.");
        assert (!has_text (notice, folder));
        assert (!has_text (notice, "file://"));
        assert (((Gtk.Label) find_named (preferences, "preferences-status")).label.contains ("unavailable"));
        window.close ();
        remove_fixture (folder);
    });
    Test.add_func ("/ui/preferences-save-failure", () => {
        string folder = fixture ();
        string config = folder + "/settings.ini";
        var window = new Music.Window (application (), config, Gst.ElementFactory.make ("fakesink", null));
        window.present ();
        wait_until (() => { return !window.loading && window.track_count == 1; });
        var preferences = open_preferences (window);
        // A directory at the file path fails deterministically, even as root.
        assert (FileUtils.unlink (config) == 0);
        assert (DirUtils.create (config, 0700) == 0);
        ((Gtk.Entry) find_named (preferences, "location")).text = folder + "/new-choice";
        ((Gtk.Button) find_named (preferences, "apply")).clicked ();
        assert (!window.loading);
        assert (window.track_count == 1);
        assert (FileUtils.test (config, FileTest.IS_DIR));
        var notice = wait_for_notice (window, "No se pudo guardar la ubicación. Revisá Preferencias.");
        assert (!has_text (notice, folder));
        assert (!has_text (notice, "file://"));
        assert (((Gtk.Label) find_named (preferences, "preferences-status")).label != "");
        assert (find_named (preferences, "apply").sensitive);
        assert (find_named (preferences, "reload").sensitive);
        window.close ();
        DirUtils.remove (config);
        remove_fixture (folder);
    });
    Test.add_func ("/ui/preferences-cancel-scan-and-close", () => {
        string folder = fixture ();
        string config = folder + "/settings.ini";
        var window = new Music.Window (application (), config, Gst.ElementFactory.make ("fakesink", null));
        window.present ();
        wait_until (() => { return !window.loading && window.track_count == 1; });
        var preferences = open_preferences (window);
        var reload = (Gtk.Button) find_named (preferences, "reload");
        reload.clicked ();
        assert (window.loading);
        foreach (string control in new string[] {"apply", "reload", "location", "browse"})
            assert (!find_named (preferences, control).sensitive);
        assert (find_named (preferences, "cancel").sensitive);
        ((Gtk.Button) find_named (preferences, "cancel")).clicked ();
        wait_until (() => { return !window.loading; });
        assert (window.track_count == 1);
        assert (has_text (find_named (window, "tracks"), "song"));
        assert (((Gtk.Label) find_named (preferences, "preferences-status")).label.contains ("cancelada"));
        assert (!has_text (window, "Carga cancelada"));
        assert (find_toast (window) == null);
        assert (new Music.LocationSettings (config).load () == File.new_for_path (folder).get_uri ());
        assert (reload.sensitive);
        assert (!find_named (preferences, "cancel").sensitive);
        reload.clicked ();
        assert (window.loading);
        window.close ();
        wait_until (() => { return !window.loading; });
        assert (!window.visible);
        remove_fixture (folder);
    });
    Test.add_func ("/ui/playback-error-detail-in-preferences", () => {
        string folder = fixture ();
        string filename = "private-track.wav";
        string path = folder + "/" + filename;
        string uri = File.new_for_path (path).get_uri ();
        assert (FileUtils.rename (folder + "/song.wav", path) == 0);
        uint8[] audio = {};
        try { FileUtils.get_data (path, out audio); }
        catch (Error e) { error ("%s", e.message); }
        var sink = Gst.ElementFactory.make ("fakesink", null);
        assert (sink != null);
        sink.set ("sync", true);
        var window = new Music.Window (application (), folder + "/settings.ini", sink);
        window.present ();
        wait_until (() => { return !window.loading && window.track_count == 1; });
        var preferences = open_preferences (window);
        var detail = (Gtk.Label) find_named (preferences, "preferences-status");
        string loaded_status = detail.label;
        preferences.close ();
        // Only remove the audio after discovery, then exercise the real error via fakesink.
        assert (FileUtils.unlink (path) == 0);
        var play = find_play (window);
        var previous = (Gtk.Button) play.get_parent ().get_first_child ();
        var next = (Gtk.Button) play.get_parent ().get_last_child ();
        assert (play.sensitive && !previous.sensitive && !next.sensitive);
        play.clicked ();
        string message = "No se pudo reproducir. Revisá Preferencias.";
        var notice = wait_for_notice (window, message);
        // Also process queued GStreamer errors after a synchronous start failure.
        while (MainContext.default ().pending ()) MainContext.default ().iteration (false);
        Test.message ("Preferences detail: %s", detail.label);
        assert (!has_text (notice, folder));
        assert (!has_text (notice, uri));
        assert (!has_text (notice, filename));
        assert (has_text (notice, message));
        assert (play.sensitive && !previous.sensitive && !next.sensitive);
        assert (open_preferences (window) == preferences);
        assert (detail.label != "");
        assert (detail.label != loaded_status);
        assert (detail.label != message);
        assert (find_named (preferences, "apply").sensitive);
        assert (find_named (preferences, "reload").sensitive);
        assert (window.track_count == 1);
        preferences.close ();
        // The playback error must leave the existing library usable for a retry.
        try { FileUtils.set_data (path, audio); }
        catch (Error e) { error ("%s", e.message); }
        assert (play.sensitive);
        play.clicked ();
        wait_until (() => { return play.icon_name == "media-playback-pause-symbolic"; });
        wait_until (() => { return detail.label == "Fin de la cola"; });
        assert (play.sensitive && !previous.sensitive && !next.sensitive);
        preferences.close ();
        wait_until (() => { return !has_text (window, message); });
        assert (!has_text (window, "Fin de la cola"));
        assert (find_named (window, "library-status") == null);
        window.close ();
        FileUtils.unlink (path);
        remove_fixture (folder);
    });
    Test.add_func ("/ui/close-stops-widget-updates", () => {
        string folder = fixture ();
        var sink = Gst.ElementFactory.make ("fakesink", null);
        sink.set ("sync", true);
        var window = new Music.Window (application (), folder + "/settings.ini", sink);
        window.present ();
        wait_until (() => { return !window.loading && window.track_count == 1; });
        var play = find_play (window);
        play.clicked ();
        wait_until (() => { return play.icon_name == "media-playback-pause-symbolic"; });
        bool closing = false;
        play.notify["icon-name"].connect (() => { assert (!closing); });
        closing = true;
        window.close ();
        assert (!window.visible);
        remove_fixture (folder);
    });
    Test.add_func ("/ui/compact-footer-layout", () => {
        string folder = fixture ();
        var window = new Music.Window (application (), folder + "/settings.ini", Gst.ElementFactory.make ("fakesink", null));
        window.present ();
        wait_until (() => { return !window.loading && window.track_count == 1; });
        var bar = find_named (window, "controls");
        foreach (int width in new int[] {1280, 1600}) {
            window.set_default_size (width, 800);
            wait_for_layout (bar);
            int occupied = bar.get_allocated_height () + bar.margin_top + bar.margin_bottom;
            Test.message ("Footer at %d×%d: allocated=%d, vertical margins=%d, occupied=%d",
                window.get_width (), window.get_height (), bar.get_allocated_height (),
                bar.margin_top + bar.margin_bottom, occupied);
            assert (occupied <= 96);
            var play = find_play (bar);
            var transport = play.get_parent ();
            var transport_bounds = bounds_in (transport, bar);
            assert ((transport_bounds.get_center ().x - bar.get_width () / 2.0f).abs () <= 2);
            for (var button = transport.get_first_child (); button != null; button = button.get_next_sibling ()) {
                var target = bounds_in (button, bar);
                Test.message ("Transport target: %.0f×%.0f (content %d×%d)",
                    target.get_width (), target.get_height (), button.get_width (), button.get_height ());
                assert (target.get_width () >= 32);
                assert (target.get_height () >= 32);
            }
            var progress = find_named (bar, "position");
            var elapsed = find_named (bar, "elapsed");
            var duration = find_named (bar, "duration");
            assert (progress != null && elapsed != null && duration != null);
            var p = bounds_in (progress, bar);
            var e = bounds_in (elapsed, bar);
            var d = bounds_in (duration, bar);
            assert (e.get_x () + e.get_width () <= p.get_x ());
            assert (p.get_x () + p.get_width () <= d.get_x ());
            assert ((e.get_center ().y - p.get_center ().y).abs () <= 2);
            assert ((d.get_center ().y - p.get_center ().y).abs () <= 2);
            assert (transport_bounds.get_y () + transport_bounds.get_height () <= p.get_y ());
            var title = (Gtk.Label) find_named (bar, "now-playing");
            assert (title.ellipsize == Pango.EllipsizeMode.END);
            title.label = string.nfill (200, 'W') + "\n" + string.nfill (200, 'W');
            wait_for_layout (bar);
            var left = bounds_in (title.get_parent (), bar);
            var middle = bounds_in (progress.get_parent ().get_parent (), bar);
            var volume = bounds_in (find_named (bar, "volume").get_parent (), bar);
            assert (left.get_x () + left.get_width () <= middle.get_x ());
            assert (middle.get_x () + middle.get_width () <= volume.get_x ());
            assert (bar.get_allocated_height () + bar.margin_top + bar.margin_bottom <= 96);
            // Window content excludes the compositor's invisible resize border.
            assert (window.get_surface ().get_width () == width);
        }
        window.close ();
        remove_fixture (folder);
    });
    Test.add_func ("/ui/footer-keyboard-playback", () => {
        string folder = fixture ("8");
        try {
            File.new_for_path (folder + "/song.wav").copy (File.new_for_path (folder + "/track-two.wav"), FileCopyFlags.NONE);
        } catch (Error e) { error ("%s", e.message); }
        var sink = Gst.ElementFactory.make ("fakesink", null);
        sink.set ("sync", true);
        var window = new Music.Window (application (), folder + "/settings.ini", sink);
        window.present ();
        wait_until (() => { return !window.loading && window.track_count == 2; });
        var bar = find_named (window, "controls");
        var play = find_play (bar);
        var previous = (Gtk.Button) play.get_parent ().get_first_child ();
        var next = (Gtk.Button) play.get_parent ().get_last_child ();
        var position = (Gtk.Scale) find_named (bar, "position");
        var volume = (Gtk.Scale) find_named (bar, "volume");
        var elapsed = (Gtk.Label) find_named (bar, "elapsed");
        var duration = (Gtk.Label) find_named (bar, "duration");
        var title = (Gtk.Label) find_named (bar, "now-playing");
        assert (!position.sensitive);
        assert (play.grab_focus ());
        assert (window.get_focus () == play);
        assert (((Gtk.Widget) play).activate ());
        wait_until (() => { return play.icon_name == "media-playback-pause-symbolic" && position.sensitive; });
        assert (title.label.has_prefix ("song\n"));
        assert (duration.label == "0:08");
        wait_until (() => { return elapsed.label == "0:01"; });
        assert (((Gtk.Widget) play).activate ());
        wait_until (() => { return play.icon_name == "media-playback-start-symbolic"; });
        assert (!previous.sensitive && play.sensitive && next.sensitive);
        assert (!previous.grab_focus ());
        assert (play.grab_focus ());
        foreach (var control in new Gtk.Widget[] {next, position, volume}) {
            assert (bar.child_focus (Gtk.DirectionType.TAB_FORWARD));
            assert (window.get_focus () == control);
        }
        double old_volume = volume.get_value ();
        volume.move_slider (Gtk.ScrollType.STEP_LEFT);
        assert (volume.get_value () < old_volume);
        assert (position.grab_focus ());
        position.change_value (Gtk.ScrollType.JUMP, 3);
        wait_until (() => { return elapsed.label == "0:03"; });
        capture_if_requested (window);
        assert (next.grab_focus ());
        assert (((Gtk.Widget) next).activate ());
        wait_until (() => { return title.label.has_prefix ("track-two\n"); });
        assert (previous.sensitive && play.sensitive && !next.sensitive);
        assert (!next.grab_focus ());
        assert (previous.grab_focus ());
        foreach (var control in new Gtk.Widget[] {play, position, volume}) {
            assert (bar.child_focus (Gtk.DirectionType.TAB_FORWARD));
            assert (window.get_focus () == control);
        }
        assert (previous.grab_focus ());
        assert (((Gtk.Widget) previous).activate ());
        wait_until (() => { return title.label.has_prefix ("song\n"); });
        assert (!previous.sensitive && play.sensitive && next.sensitive);
        window.close ();
        FileUtils.unlink (folder + "/track-two.wav");
        remove_fixture (folder);
    });
    Test.add_func ("/ui/footer-volume-group", () => {
        string folder = fixture ();
        var window = new Music.Window (application (), folder + "/settings.ini", Gst.ElementFactory.make ("fakesink", null));
        window.present ();
        wait_until (() => { return !window.loading; });
        var bar = find_named (window, "controls");
        wait_for_layout (bar);
        var volume = find_named (bar, "volume");
        var icon = bounds_in (volume.get_prev_sibling (), bar);
        var slider = bounds_in (volume, bar);
        float gap = slider.get_x () - icon.get_x () - icon.get_width ();
        Test.message ("Volume icon/slider gap: %.0f", gap);
        assert (gap >= 0 && gap <= 6);
        window.close ();
        remove_fixture (folder);
    });
    Test.add_func ("/ui/library-panel-free-width", () => {
        string folder = fixture ();
        var window = new Music.Window (application (), folder + "/settings.ini", Gst.ElementFactory.make ("fakesink", null));
        window.present ();
        wait_until (() => { return !window.loading && window.track_count == 1; });
        var panels = (Gtk.Paned) find_named (window, "library").get_ancestor (typeof (Gtk.Paned));
        foreach (int width in new int[] {1280, 1000}) {
            window.set_default_size (width, 800);
            wait_for_layout (window);
            panels.position = 4;
            wait_for_layout (window);
            Test.message ("Library at %d: position=%d, allocated=%d", width,
                panels.position, panels.start_child.get_allocated_width ());
            assert (panels.position == 4);
            assert (panels.start_child.get_allocated_width () <= 4);
            var start = bounds_in (panels.start_child, panels);
            var end = bounds_in (panels.end_child, panels);
            assert (start.get_x () + start.get_width () <= end.get_x ());
            assert (window.get_surface ().get_width () == width);
        }
        window.close ();
        remove_fixture (folder);
    });
    Test.add_func ("/ui/tracks-details-free-width", () => {
        string folder = fixture ();
        var window = new Music.Window (application (), folder + "/settings.ini", Gst.ElementFactory.make ("fakesink", null));
        window.present ();
        wait_until (() => { return !window.loading && window.track_count == 1; });
        var inner = (Gtk.Paned) find_named (window, "tracks").get_ancestor (typeof (Gtk.Paned));
        foreach (int width in new int[] {1280, 1000}) {
            window.set_default_size (width, 800);
            wait_for_layout (window);
            inner.position = 4;
            wait_for_layout (window);
            Test.message ("Tracks at %d: position=%d, allocated=%d", width,
                inner.position, inner.start_child.get_width ());
            assert (inner.position == 4);
            assert (inner.start_child.get_width () == 4);
            inner.position = inner.get_width () - 10;
            wait_for_layout (window);
            Test.message ("Details at %d: position=%d/%d, allocated=%d", width,
                inner.position, inner.get_width (), inner.end_child.get_width ());
            assert (inner.end_child.get_width () <= 10);
            var start = bounds_in (inner.start_child, inner);
            var end = bounds_in (inner.end_child, inner);
            assert (start.get_x () + start.get_width () <= end.get_x ());
            assert (end.get_x () + end.get_width () <= inner.get_width ());
            assert (window.get_surface ().get_width () == width);
        }
        window.close ();
        remove_fixture (folder);
    });
    Test.add_func ("/ui/panels-extremes-and-restore", () => {
        string folder = fixture ("8");
        var sink = Gst.ElementFactory.make ("fakesink", null);
        sink.set ("sync", true);
        var window = new Music.Window (application (), folder + "/settings.ini", sink);
        window.present ();
        wait_until (() => { return !window.loading && window.track_count == 1; });
        var library = find_named (window, "library");
        var tracks = find_named (window, "tracks");
        var details = find_named (window, "details");
        var outer = (Gtk.Paned) library.get_ancestor (typeof (Gtk.Paned));
        var inner = (Gtk.Paned) tracks.get_ancestor (typeof (Gtk.Paned));
        var play = find_play (window);
        play.clicked ();
        wait_until (() => { return play.icon_name == "media-playback-pause-symbolic"; });
        play.clicked ();
        wait_until (() => { return play.icon_name == "media-playback-start-symbolic"; });
        foreach (int width in new int[] {1280, 1000}) {
            window.set_default_size (width, 800);
            wait_for_layout (window);
            var tabs = bounds_in (details.get_first_child (), inner.end_child);
            Test.message ("Initial details at %d: tabs end=%.0f, panel width=%d", width,
                tabs.get_x () + tabs.get_width (), inner.end_child.get_width ());
            assert (tabs.get_x () >= 0);
            assert (tabs.get_x () + tabs.get_width () <= inner.end_child.get_width ());
            capture_if_requested (window, "-initial-%d".printf (width));
            int initial_outer = outer.position;
            int initial_inner = inner.position;
            foreach (int outer_edge in new int[] {0, 4, outer.get_width () - 10, outer.get_width ()}) {
                outer.position = outer_edge;
                wait_for_layout (window);
                Test.message ("Outer at %d: requested=%d position=%d, children=%d/%d", width,
                    outer_edge, outer.position, outer.start_child.get_width (), outer.end_child.get_width ());
                assert (outer.min_position == 0);
                assert (outer.max_position >= outer.get_width () - 10);
                if (outer_edge < 10) assert (outer.start_child.get_width () <= 4);
                else assert (outer.end_child.get_width () <= 5);
                // Even at the extremes the outer handle must remain pickable,
                // rather than being covered by overflowing panel content.
                Gtk.Widget? handle = null;
                for (var child = outer.get_first_child (); child != null; child = child.get_next_sibling ())
                    if (child.get_css_name () == "separator") handle = child;
                assert (handle != null);
                var handle_bounds = bounds_in (handle, window);
                assert (window.pick (handle_bounds.get_center ().x, handle_bounds.get_center ().y,
                    Gtk.PickFlags.DEFAULT) == handle);
                foreach (int inner_edge in new int[] {0, inner.get_width (), 2}) {
                    inner.position = inner_edge;
                    wait_for_layout (window);
                    Test.message ("Inner in outer edge %d: position=%d/%d", outer_edge, inner.position, inner.get_width ());
                    assert (inner.min_position == 0);
                    assert (inner.position >= 0);
                    assert (inner.position <= inner.get_width ());
                    assert (window.get_surface ().get_width () == width);
                }
                capture_if_requested (window, "-narrow-%d-%d".printf (width, outer_edge));
                // Restore from each end, not just the last one; neither divider
                // may disappear behind clipped content or an oversized neighbour.
                outer.position = initial_outer;
                wait_for_layout (window);
                inner.position = initial_inner;
                wait_for_layout (window);
                assert (outer.position == initial_outer);
                assert (inner.position == initial_inner);
                foreach (var split in new Gtk.Paned[] {outer, inner}) {
                    var start = bounds_in (split.start_child, split);
                    var end = bounds_in (split.end_child, split);
                    float handle_x = start.get_x () + start.get_width ();
                    assert (end.get_x () - handle_x >= 1);
                    var picked = split.pick ((handle_x + end.get_x ()) / 2, split.get_height () / 2, Gtk.PickFlags.DEFAULT);
                    assert (picked != null && picked.get_css_name () == "separator");
                }
                assert (window.track_count == 1);
                assert (find_named (window, "library") == library);
                assert (find_named (window, "tracks") == tracks);
                assert (find_named (window, "details") == details);
                assert (has_text (library, "Todas las pistas"));
                assert (has_text (tracks, "song"));
                assert (has_text (details, "Artista:"));
                assert (has_text (details, "song"));
                capture_if_requested (window, "-restored-%d".printf (width));
            }
        }
        window.close ();
        remove_fixture (folder);
    });
    return Test.run ();
}
