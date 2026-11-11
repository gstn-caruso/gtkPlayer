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
    FileUtils.unlink (folder + "/session.ini");
    DirUtils.remove (folder);
}

void close_and_flush (Music.Window window) {
    window.close ();
    bool done = false;
    window.flush_session.begin (() => { done = true; });
    wait_until (() => { return done; });
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

Gtk.Label? find_visible_label (Gtk.Widget widget, string text) {
    if (widget is Gtk.Label && widget.get_mapped () && ((Gtk.Label) widget).get_text ().contains (text))
        return (Gtk.Label) widget;
    for (var child = widget.get_first_child (); child != null; child = child.get_next_sibling ()) {
        var found = find_visible_label (child, text);
        if (found != null) return found;
    }
    return null;
}

Gtk.LinkButton? find_visible_link (Gtk.Widget widget, string uri) {
    if (widget is Gtk.LinkButton && widget.get_mapped () && ((Gtk.LinkButton) widget).uri == uri)
        return (Gtk.LinkButton) widget;
    for (var child = widget.get_first_child (); child != null; child = child.get_next_sibling ()) {
        var found = find_visible_link (child, uri);
        if (found != null) return found;
    }
    return null;
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

Gtk.ListView? find_media_list (Gtk.Widget widget) {
    if (widget is Gtk.ListView) return (Gtk.ListView) widget;
    for (var child = widget.get_first_child (); child != null; child = child.get_next_sibling ()) {
        var found = find_media_list (child);
        if (found != null) return found;
    }
    return null;
}

Gtk.Widget? bound_item (Gtk.Widget widget, Object item) {
    if (widget is Music.MediaRow) {
        var row = (Music.MediaRow) widget;
        if (item is Music.Track && row.tracks.length > 0 && row.tracks[0] == item) return row.get_parent ();
        if (item is Music.QueueEntry && row.entry_id == ((Music.QueueEntry) item).id) return row.get_parent ();
    }
    for (var child = widget.get_first_child (); child != null; child = child.get_next_sibling ()) {
        var found = bound_item (child, item);
        if (found != null) return found;
    }
    return null;
}
Gtk.Widget? list_item (Gtk.ListView list, int index) {
    if (index < 0 || index >= list.model.get_n_items ()) return null;
    wait_for_layout (list);
    return bound_item (list, list.model.get_item ((uint) index));
}
uint selected_index (Gtk.ListView list) { return ((Gtk.SingleSelection) list.model).selected; }
void show_songs (Music.Window window) {
    var modes = find_list (find_named (window, "library"));
    modes.select_row (modes.get_row_at_index (2));
    wait_for_layout (window);
}
void select_album (Gtk.Widget library, string artist, string album) {
    var window = (Music.Window) library.get_ancestor (typeof (Music.Window));
    var modes = find_list (library);
    modes.select_row (modes.get_row_at_index (0));
    modes.row_activated (modes.get_row_at_index (0));
    var grid = (Gtk.GridView) find_named (window, "album-grid");
    for (uint i = 0; i < grid.model.get_n_items (); i++) {
        var group = (Music.LibraryGroup) grid.model.get_item (i);
        if (group.artist != artist || group.title != album) continue;
        grid.activate (i);
        wait_for_layout (window);
        return;
    }
    error ("Album not found: %s / %s", artist, album);
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

class UnmountedSourceWindow : Music.Window {
    // Window starts loading from its constructor: arm the failure only after that load.
    public bool source_unmounted = false;
    public int mount_calls = 0;
    private SourceFunc? resume_mount;

    public UnmountedSourceWindow (Gtk.Application app, string config, string cache_path) {
        base (app, config, Gst.ElementFactory.make ("fakesink", null), null, cache_path);
    }

    protected override async Music.Track[] scan_source (Music.Scanner scanner, File folder,
                                                       Cancellable cancel, Music.Track[] previous) throws Error {
        if (source_unmounted) throw new IOError.NOT_MOUNTED ("Fixture sin montar");
        return yield scanner.scan (folder, cancel, previous);
    }

    protected override async void mount_source (File folder, Cancellable cancel) throws Error {
        mount_calls++;
        resume_mount = mount_source.callback;
        yield;
        cancel.set_error_if_cancelled ();
        source_unmounted = false;
    }

    public void complete_mount () {
        assert (resume_mount != null);
        Idle.add ((owned) resume_mount);
    }
}

class FastRecoveryWindow : Music.Window {
    public FastRecoveryWindow (Gtk.Application app, string config, string cache_path) {
        base (app, config, Gst.ElementFactory.make ("fakesink", null), null, cache_path);
    }

    // Configure the clock boundary, not the scanner or the filesystem monitors.
    protected override uint fallback_interval_seconds () { return 1; }
}

Gtk.Button? labeled_button (Gtk.Widget widget, string label) {
    if (widget is Gtk.Button && ((Gtk.Button) widget).label == label) return (Gtk.Button) widget;
    for (var child = widget.get_first_child (); child != null; child = child.get_next_sibling ()) {
        var found = labeled_button (child, label);
        if (found != null) return found;
    }
    return null;
}
Music.MediaRow? media_row (Gtk.Widget widget) {
    if (widget is Music.MediaRow) return (Music.MediaRow) widget;
    for (var child = widget.get_first_child (); child != null; child = child.get_next_sibling ()) {
        var found = media_row (child);
        if (found != null) return found;
    }
    return null;
}
void row_action (Gtk.ListView view, int index, string action) {
    var widget = list_item (view, index);
    assert (widget != null);
    var button = labeled_button (widget, action);
    assert (button != null);
    button.clicked ();
}

void test_visual_album_queue_actions () {
    string folder = fixture ("8");
    try {
        string[] command = {"ffmpeg", "-v", "error", "-i", folder + "/song.wav", "-metadata", "artist=Banda", "-metadata", "album=Disco", "-metadata", "title=Segunda", "-metadata", "track=2", "-y", folder + "/two.flac"};
        int status;
        Process.spawn_sync (null, command, null, SpawnFlags.SEARCH_PATH, null, null, null, out status);
        assert (status == 0);
        command = new string[] {"ffmpeg", "-v", "error", "-i", folder + "/song.wav", "-metadata", "artist=Banda", "-metadata", "album=Disco", "-metadata", "title=Primera", "-metadata", "track=1", "-y", folder + "/one.flac"};
        Process.spawn_sync (null, command, null, SpawnFlags.SEARCH_PATH, null, null, null, out status);
        assert (status == 0);
        FileUtils.unlink (folder + "/song.wav");
        var pixbuf = new Gdk.Pixbuf (Gdk.Colorspace.RGB, false, 8, 24, 24);
        pixbuf.fill (0x224488ff);
        pixbuf.save (folder + "/cover.jpg", "jpeg");
    } catch (Error e) { error ("%s", e.message); }
    var sink = Gst.ElementFactory.make ("fakesink", null);
    sink.set ("sync", true);
    var window = new Music.Window (application (), folder + "/settings.ini", sink);
    window.present ();
    wait_until (() => { return !window.loading && window.track_count == 2; });
    var grid = (Gtk.GridView) find_named (window, "album-grid");
    var queue = (Gtk.ListView) find_named (window, "queue-list");
    var play = find_play (window);
    wait_for_layout (window);
    assert (grid.get_mapped () && grid.model.get_n_items () == 1);
    labeled_button (media_row (grid), "Agregar a la cola").clicked ();
    assert (queue.model.get_n_items () == 2 && play.icon_name == "media-playback-start-symbolic");
    assert (((Music.QueueEntry) queue.model.get_item (0)).track.number == 1);
    assert (((Music.QueueEntry) queue.model.get_item (1)).track.number == 2);
    labeled_button (media_row (grid), "Reproducir ahora").clicked ();
    wait_until (() => { return play.icon_name == "media-playback-pause-symbolic"; });
    assert (queue.model.get_n_items () == 4 && selected_index (queue) == 0);
    assert (((Music.QueueEntry) queue.model.get_item (0)).id != ((Music.QueueEntry) queue.model.get_item (2)).id);
    assert (((Gtk.Image) find_named (window, "now-cover")).get_paintable () is Gdk.Texture);
    string active = ((Music.QueueEntry) queue.model.get_item (0)).id;
    row_action (queue, 2, "Mover arriba");
    assert (((Music.QueueEntry) queue.model.get_item (0)).id == active);
    assert (play.icon_name == "media-playback-pause-symbolic");
    string[] ids = {};
    for (uint i = 0; i < queue.model.get_n_items (); i++) ids += ((Music.QueueEntry) queue.model.get_item (i)).id;
    ((Gtk.Button) find_named (window, "clear-queue")).clicked ();
    assert (queue.model.get_n_items () == 1 && ((Music.QueueEntry) queue.model.get_item (0)).id == active);
    ((Gtk.Button) find_named (window, "undo-queue")).clicked ();
    for (uint i = 0; i < ids.length; i++) assert (((Music.QueueEntry) queue.model.get_item (i)).id == ids[i]);
    var stop_after = (Gtk.CheckButton) find_named (window, "stop-after-current");
    assert (stop_after != null);
    stop_after.active = true;
    assert (stop_after.active);
    queue.activate (2);
    assert (!stop_after.active);
    assert (queue.model.get_n_items () == 4 && selected_index (queue) == 2);
    row_action (queue, 2, "Quitar de la cola");
    wait_until (() => { return play.icon_name == "media-playback-pause-symbolic"; });
    assert (queue.model.get_n_items () == 3 && selected_index (queue) == 2);
    var search = (Gtk.SearchEntry) find_named (window, "library-search");
    foreach (string query in new string[] {"BANDA", "disco", "primera"}) {
        search.text = query;
        search.search_changed ();
        wait_for_layout (window);
        assert (grid.model.get_n_items () == 1);
        var group = (Music.LibraryGroup) grid.model.get_item (0);
        assert (group.tracks.length == (query == "primera" ? 1 : 2));
    }
    grid.activate (0);
    wait_for_layout (window);
    var back = (Gtk.Button) find_named (window, "library-back");
    assert (back.get_mapped ());
    back.clicked ();
    wait_for_layout (window);
    assert (grid.get_mapped () && !back.get_mapped ());
    search.text = "sin coincidencias";
    search.search_changed ();
    assert (grid.model.get_n_items () == 0 && has_text (window, "Sin resultados"));
    close_and_flush (window);
    foreach (string file in new string[] {"one.flac", "two.flac", "cover.jpg"}) FileUtils.unlink (folder + "/" + file);
    remove_fixture (folder);
}

void test_queue_import_drop_and_cancel () {
    string folder = fixture ("8");
    try { FileUtils.set_contents (folder + "/broken.flac", "bad audio"); } catch (Error e) { error ("%s", e.message); }
    var window = new Music.Window (application (), folder + "/settings.ini", Gst.ElementFactory.make ("fakesink", null));
    window.present ();
    wait_until (() => { return !window.loading; });
    var queue = (Gtk.ListView) find_named (window, "queue-list");
    var controllers = find_named (window, "queue-drop-area").observe_controllers ();
    Gtk.DropTarget? target = null;
    for (uint i = 0; i < controllers.get_n_items (); i++) {
        var candidate = controllers.get_item (i) as Gtk.DropTarget;
        if (candidate != null) target = candidate;
    }
    assert (target != null);
    var files = new Gdk.FileList.from_array ({File.new_for_path (folder + "/song.wav"), File.new_for_path (folder + "/broken.flac")});
    Value payload = Value (typeof (Gdk.FileList));
    payload.set_boxed (files);
    assert (target.on_drop (payload, 10, 10));
    wait_until (() => { return queue.model.get_n_items () == 1 && !find_named (window, "cancel-import").get_mapped (); });
    assert (find_play (window).icon_name == "media-playback-start-symbolic");
    wait_for_notice (window, "1 pista agregada · 1 archivo omitido");
    bool done = false;
    window.import_files.begin ({File.new_for_path (folder)}, -1, () => { done = true; });
    ((Gtk.Button) find_named (window, "cancel-import")).clicked ();
    wait_until (() => { return done; });
    assert (queue.model.get_n_items () == 1);
    done = false;
    window.import_files.begin ({File.new_for_path (folder + "/song.wav"), File.new_for_path (folder + "/absent")}, -1, () => { done = true; });
    wait_until (() => { return done; });
    assert (queue.model.get_n_items () == 1);
    wait_for_notice (window, "No se pudieron importar los archivos");
    assert (new Music.LocationSettings (folder + "/settings.ini").load () == File.new_for_path (folder).get_uri ());
    // Internal copy uses its own payload, preserving duplicate identities.
    var entry = (Music.QueueEntry) queue.model.get_item (0);
    Value internal_payload = Value (typeof (Music.QueueDrag));
    internal_payload.set_object (new Music.QueueDrag ({entry.track}));
    assert (target.on_drop (internal_payload, 10, 10000));
    assert (queue.model.get_n_items () == 2 && ((Music.QueueEntry) queue.model.get_item (1)).id != entry.id);
    internal_payload.set_object (new Music.QueueDrag ({entry.track}, entry.id));
    assert (target.on_drop (internal_payload, 10, 10000));
    assert (((Music.QueueEntry) queue.model.get_item (1)).id == entry.id);
    close_and_flush (window);
    FileUtils.unlink (folder + "/broken.flac");
    remove_fixture (folder);
}

void test_queue_session_reopen () {
    string folder = fixture ("8");
    var sink = Gst.ElementFactory.make ("fakesink", null);
    sink.set ("sync", true);
    var app = application ();
    var window = new Music.Window (app, folder + "/settings.ini", sink);
    window.present ();
    wait_until (() => { return !window.loading; });
    show_songs (window);
    var songs = (Gtk.ListView) find_named (window, "song-list");
    row_action (songs, 0, "Agregar a la cola");
    row_action (songs, 0, "Reproducir ahora");
    wait_until (() => { return find_play (window).icon_name == "media-playback-pause-symbolic"; });
    var position = (Gtk.Scale) find_named (window, "position");
    wait_until (() => { return position.sensitive; });
    position.change_value (Gtk.ScrollType.JUMP, 3);
    wait_until (() => { return ((Gtk.Label) find_named (window, "elapsed")).label == "0:03"; });
    var queue = (Gtk.ListView) find_named (window, "queue-list");
    string active = ((Music.QueueEntry) queue.model.get_item (selected_index (queue))).id;
    close_and_flush (window);
    sink = Gst.ElementFactory.make ("fakesink", null);
    sink.set ("sync", true);
    var reopened = new Music.Window (app, folder + "/settings.ini", sink);
    reopened.present ();
    var restored = (Gtk.ListView) find_named (reopened, "queue-list");
    wait_until (() => { return !reopened.loading && restored.model.get_n_items () == 2; });
    assert (find_play (reopened).icon_name == "media-playback-start-symbolic");
    assert (((Music.QueueEntry) restored.model.get_item (selected_index (restored))).id == active);
    wait_until (() => { return ((Gtk.Label) find_named (reopened, "elapsed")).label == "0:03"; });
    find_play (reopened).clicked ();
    wait_until (() => {
        return find_play (reopened).icon_name == "media-playback-pause-symbolic" &&
            ((Gtk.Label) find_named (reopened, "elapsed")).label == "0:03";
    });
    close_and_flush (reopened);
    remove_fixture (folder);
}

void test_adaptive_overlays_restore_proportions () {
    string folder = fixture ();
    var window = new Music.Window (application (), folder + "/settings.ini", Gst.ElementFactory.make ("fakesink", null));
    window.present ();
    wait_until (() => { return !window.loading; });
    wait_for_layout (window);
    var left = find_named (window, "library");
    var right = find_named (window, "details");
    var panels = (Gtk.Paned) left.get_ancestor (typeof (Gtk.Paned));
    var inner = (Gtk.Paned) right.get_ancestor (typeof (Gtk.Paned));
    panels.position = 300;
    inner.position = 570;
    wait_for_layout (window);
    double left_proportion = (double) panels.position / panels.get_width ();
    double inner_proportion = (double) inner.position / inner.get_width ();
    window.set_default_size (1024, 600);
    wait_for_layout (window);
    assert (window.get_surface ().get_width () == 1024 && window.get_surface ().get_height () == 600);
    var show_library = (Gtk.Button) find_named (window, "show-library");
    var show_details = (Gtk.Button) find_named (window, "show-details");
    assert (show_library.get_mapped () && show_details.get_mapped ());
    assert (left.get_ancestor (typeof (Gtk.Paned)) == null);
    assert (right.get_ancestor (typeof (Gtk.Paned)) == null);
    show_library.clicked ();
    wait_until (() => { return ((Adw.OverlaySplitView) left.get_ancestor (typeof (Adw.OverlaySplitView))).show_sidebar; });
    show_library.clicked ();
    show_details.clicked ();
    wait_for_layout (window);
    var toggle = (Adw.OverlaySplitView) right.get_ancestor (typeof (Adw.OverlaySplitView));
    assert (toggle.show_sidebar);
    var queue = find_named (window, "queue-list");
    wait_until (() => {
        var q = bounds_in (queue, window);
        return q.get_x () >= 0 && q.get_x () + q.get_width () <= window.get_width ();
    });
    capture_if_requested (window, "-1024");
    var settings = Gtk.Settings.get_default ();
    string original_font = settings.gtk_font_name;
    settings.gtk_font_name = "Sans 18";
    wait_for_layout (window);
    assert (window.get_surface ().get_width () == 1024 && window.get_surface ().get_height () == 600);
    var controls = bounds_in (find_named (window, "controls"), window);
    assert (controls.get_y () >= 0 && controls.get_y () + controls.get_height () <= window.get_height ());
    capture_if_requested (window, "-1024-large-text");
    settings.gtk_font_name = original_font;
    toggle.show_sidebar = false;
    window.set_default_size (1600, 800);
    wait_for_layout (window);
    assert (left.get_ancestor (typeof (Gtk.Paned)) == panels && right.get_ancestor (typeof (Gtk.Paned)) == inner);
    wait_until (() => {
        return ((double) panels.position / panels.get_width () - left_proportion).abs () < 0.01 &&
            ((double) inner.position / inner.get_width () - inner_proportion).abs () < 0.01;
    });
    Test.message ("Restored inner proportion %.4f, expected %.4f (%d/%d)", (double) inner.position / inner.get_width (), inner_proportion, inner.position, inner.get_width ());
    assert (((double) inner.position / inner.get_width () - inner_proportion).abs () < 0.01);
    close_and_flush (window);
    remove_fixture (folder);
}

void test_initial_empty_states_survive_navigation () {
    string folder = fixture ();
    FileUtils.unlink (folder + "/song.wav");
    var window = new Music.Window (application (), folder + "/settings.ini", Gst.ElementFactory.make ("fakesink", null));
    window.present ();
    // Cancellation is requested before the initial cache read completes.
    var preferences = open_preferences (window);
    ((Gtk.Button) find_named (preferences, "cancel")).clicked ();
    wait_until (() => { return !window.loading; });
    preferences.close ();
    var modes = find_list (find_named (window, "library"));
    foreach (int page in new int[] {0, 1, 2}) {
        modes.select_row (modes.get_row_at_index (page));
        assert (has_text (window, "Carga cancelada"));
        assert (!has_text (window, "La música aparecerá aquí al terminar la carga"));
    }
    window.load_library.begin (folder + "/missing");
    modes.select_row (modes.get_row_at_index (0));
    assert (has_text (window, "Leyendo biblioteca…"));
    wait_until (() => { return !window.loading; });
    foreach (int page in new int[] {1, 2, 0}) {
        modes.select_row (modes.get_row_at_index (page));
        assert (has_text (window, "No se pudo cargar la biblioteca"));
        assert (!has_text (window, "Biblioteca vacía"));
    }
    close_and_flush (window);
    remove_fixture (folder);
}

string xwindow_id (string title) {
    try {
        string output;
        int status;
        Process.spawn_sync (null, {"xdotool", "search", "--onlyvisible", "--name", "^" + title + "$"}, null,
            SpawnFlags.SEARCH_PATH, null, out output, null, out status);
        assert (status == 0);
        return output.strip ();
    } catch (Error e) { error ("xdotool: %s", e.message); }
}
void pointer_drag (string source, float sx, float sy, string target, float tx, float ty, bool cancel = false) {
    try {
        string[] command = {"xdotool", "windowfocus", source, "mousemove", "--window", source, ((int) sx).to_string (), ((int) sy).to_string (),
            "mousedown", "1", "sleep", "0.12", "mousemove", "--window", source, ((int) sx + 22).to_string (), ((int) sy + 12).to_string (),
            "sleep", "0.2", "mousemove", "--window", target, ((int) tx).to_string (), ((int) ty).to_string (), "sleep", "0.2", "mousemove", "--window", target, ((int) tx + 2).to_string (), ((int) ty + 2).to_string (), "sleep", "0.3"};
        if (cancel) { command += "key"; command += "Escape"; command += "sleep"; command += "0.15"; }
        command += "mouseup"; command += "1";
        Process.spawn_async (null, command, null, SpawnFlags.SEARCH_PATH, null, null);
    } catch (Error e) { error ("xdotool: %s", e.message); }
}
void test_native_pointer_drag () {
    if (Environment.get_variable ("GTKPLAYER_TEST_POINTER") != "1" || Environment.find_program_in_path ("xdotool") == null) {
        Test.skip ("Arrastre X11 opcional: GTKPLAYER_TEST_POINTER=1 y xdotool");
        return;
    }
    string folder = fixture ("8");
    var window = new Music.Window (application (), folder + "/settings.ini", Gst.ElementFactory.make ("fakesink", null));
    window.title = "GTK Player Drag Test";
    window.present ();
    wait_until (() => { return !window.loading; });
    wait_for_layout (window);
    var grid = find_named (window, "album-grid");
    var queue = (Gtk.ListView) find_named (window, "queue-list");
    string target = xwindow_id (window.title);
    var artwork = bounds_in (media_row (grid).artwork, window);
    var destination = bounds_in (queue, window);
    Test.message ("Dragging album to queue: %s at %.0f,%.0f to %.0f,%.0f", target, artwork.get_center ().x, artwork.get_center ().y, destination.get_center ().x, destination.get_y () + 80);
    pointer_drag (target, artwork.get_center ().x, artwork.get_center ().y, target, destination.get_center ().x, destination.get_y () + 80);
    wait_until (() => { return queue.model.get_n_items () == 1; });
    Test.message ("Internal album copied");
    string first = ((Music.QueueEntry) queue.model.get_item (0)).id;
    // A separate native window provides the same Gdk.FileList type as a file manager.
    var external = new Gtk.Window ();
    external.title = "GTK Player File Drag Fixture";
    external.set_default_size (180, 120);
    var label = new Gtk.Label ("Archivo de audio");
    var source = new Gtk.DragSource ();
    source.actions = Gdk.DragAction.COPY;
    source.prepare.connect (() => {
        Value value = Value (typeof (Gdk.FileList));
        value.set_boxed (new Gdk.FileList.from_array ({File.new_for_path (folder + "/song.wav")}));
        return new Gdk.ContentProvider.for_value (value);
    });
    label.add_controller (source);
    external.child = label;
    external.present ();
    wait_for_layout (external);
    string external_id = xwindow_id (external.title);
    try {
        int status;
        Process.spawn_sync (null, {"xdotool", "windowmove", external_id, "1400", "10"}, null,
            SpawnFlags.SEARCH_PATH, null, null, null, out status);
        assert (status == 0);
    } catch (Error e) { error ("%s", e.message); }
    pointer_drag (external_id, 70, 60, target, destination.get_center ().x, destination.get_y () + 160);
    wait_until (() => { return queue.model.get_n_items () == 2; });
    Test.message ("External Gdk.FileList imported");
    external.destroy ();
    var row = media_row (list_item (queue, 0));
    var from = bounds_in (row, window);
    pointer_drag (target, from.get_x () + 30, from.get_center ().y, target, destination.get_center ().x, destination.get_y () + 250);
    wait_until (() => { return ((Music.QueueEntry) queue.model.get_item (1)).id == first; });
    Test.message ("Queue entry moved");
    pointer_drag (target, artwork.get_center ().x, artwork.get_center ().y, target, destination.get_center ().x, destination.get_y () + 250, true);
    bool settled = false;
    Timeout.add (1300, () => { settled = true; return Source.REMOVE; });
    wait_until (() => { return settled; });
    assert (queue.model.get_n_items () == 2);
    assert (find_play (window).icon_name == "media-playback-start-symbolic");
    try { Process.spawn_async (null, {"xdotool", "key", "ctrl+f"}, null, SpawnFlags.SEARCH_PATH, null, null); }
    catch (Error e) { error ("%s", e.message); }
    wait_until (() => {
        var search = find_named (window, "library-search");
        var focus = window.get_focus ();
        return focus != null && (focus == search || focus.is_ancestor (search));
    });
    close_and_flush (window);
    remove_fixture (folder);
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
        assert (find_named (window, "library-search") is Gtk.SearchEntry);
        assert (find_named (window, "open-preferences") != null);
        wait_until (() => { return !window.loading && window.track_count == 1; });
        assert (new Music.LocationSettings (config).load () == File.new_for_path (folder).get_uri ());
        wait_for_layout (window);
        assert (((Gtk.GridView) find_named (window, "album-grid")).get_mapped ());
        assert (has_text (find_named (window, "tracks"), "Sin álbum"));
        assert (has_text (find_named (window, "controls"), "Nada en reproducción"));
        capture_if_requested (window);
        close_and_flush (window);
        var reopened = new Music.Window (app, config, Gst.ElementFactory.make ("fakesink", null));
        reopened.present ();
        wait_until (() => { return !reopened.loading && reopened.track_count == 1; });
        close_and_flush (reopened);
        remove_fixture (folder);
    });
    Test.add_func ("/ui/givenKnownUnmountedLibrary_whenAutomaticallyLoadedThenManuallyReloaded_thenOnlyManualLoadMountsWithoutHidingTracks", () => {
        string folder = fixture ();
        try {
            string cache_path = DirUtils.make_tmp ("gtkplayer-ui-mount-cache-XXXXXX");
            string source_uri = File.new_for_path (folder).get_uri ();
            var window = new UnmountedSourceWindow (application (), folder + "/settings.ini", cache_path);
            window.present ();
            wait_until (() => { return !window.loading; });
        show_songs (window);
            assert_cmpuint (window.track_count, CompareOperator.EQ, 1);
            wait_until (() => { return find_visible_label (find_named (window, "tracks"), "song") != null; });
            // Establish a real, persisted snapshot before injecting the network failure.
            var stored = new Music.LibraryCache (cache_path).load (source_uri);
            assert_cmpint (stored.length, CompareOperator.EQ, 1);
            assert_cmpstr (stored[0].uri, CompareOperator.EQ, File.new_for_path (folder + "/song.wav").get_uri ());
            window.source_unmounted = true;

            bool automatic_done = false;
            window.load_library.begin (source_uri, true, (obj, result) => {
                window.load_library.end (result);
                automatic_done = true;
            });
            wait_until (() => { return automatic_done; });
            assert (!window.loading);
            assert_cmpint (window.mount_calls, CompareOperator.EQ, 0);
            assert_cmpuint (window.track_count, CompareOperator.EQ, 1);
            wait_for_layout (window);
            assert_nonnull (find_visible_label (find_named (window, "tracks"), "song"));
            assert_null (find_toast (window));

            var preferences = open_preferences (window);
            ((Gtk.Button) find_named (preferences, "reload")).clicked ();
            wait_until (() => { return window.mount_calls > 0 || !window.loading; });
            assert_cmpint (window.mount_calls, CompareOperator.EQ, 1);
            assert (window.loading);
            assert_cmpuint (window.track_count, CompareOperator.EQ, 1);
            assert_nonnull (find_visible_label (find_named (window, "tracks"), "song"));
            assert (has_text (preferences, "Conectando con la ubicación…"));

            window.complete_mount ();
            wait_until (() => { return !window.loading; });
            assert_cmpint (window.mount_calls, CompareOperator.EQ, 1);
            assert_cmpuint (window.track_count, CompareOperator.EQ, 1);
            wait_until (() => { return find_visible_label (find_named (window, "tracks"), "song") != null; });
            assert (has_text (preferences, "1 pista cargada"));
            assert_null (find_toast (window));
            preferences.close ();
            close_and_flush (window);

            var cache_files = File.new_for_path (cache_path).enumerate_children (FileAttribute.STANDARD_NAME, FileQueryInfoFlags.NONE);
            FileInfo? entry;
            while ((entry = cache_files.next_file ()) != null) cache_files.get_child (entry).delete ();
            cache_files.close ();
            File.new_for_path (cache_path).delete ();
        } catch (Error e) { error ("Fixture de reconexión manual con caché: %s", e.message); }
        remove_fixture (folder);
    });
    Test.add_func ("/ui/givenCachedLibrary_whenSourceIsUnavailable_thenReopenedWindowShowsKnownTracks", () => {
        try {
            string root = DirUtils.make_tmp ("gtkplayer-ui-cache-XXXXXX");
            string audio = root + "/audio";
            string settings = root + "/settings";
            string cache_path = root + "/cache";
            File.new_for_path (audio).make_directory ();
            File.new_for_path (settings).make_directory ();
            File.new_for_path (cache_path).make_directory ();
            string[] command = {"ffmpeg", "-v", "error", "-f", "lavfi", "-i", "sine=duration=0.2", "-y", audio + "/song.wav"};
            int status;
            Process.spawn_sync (null, command, null, SpawnFlags.SEARCH_PATH, null, null, null, out status);
            assert_cmpint (status, CompareOperator.EQ, 0);
            string config = settings + "/settings.ini";
            string source_uri = File.new_for_path (audio).get_uri ();
            new Music.LocationSettings (config).save (source_uri);

            var app = application ();
            var window = new Music.Window (app, config, Gst.ElementFactory.make ("fakesink", null), null, cache_path);
            window.present ();
            wait_until (() => { return !window.loading; });
        show_songs (window);
            assert_cmpuint (window.track_count, CompareOperator.EQ, 1);
            wait_until (() => { return find_visible_label (find_named (window, "tracks"), "song") != null; });
            close_and_flush (window);

            // Only Window writes the cache: a fresh reader verifies real persistence.
            var stored = new Music.LibraryCache (cache_path).load (source_uri);
            assert_cmpint (stored.length, CompareOperator.EQ, 1);
            assert_cmpstr (stored[0].uri, CompareOperator.EQ, File.new_for_path (audio + "/song.wav").get_uri ());
            assert_cmpstr (stored[0].title, CompareOperator.EQ, "song");
            assert_cmpint (FileUtils.rename (audio, root + "/audio-offline"), CompareOperator.EQ, 0);
            assert (!FileUtils.test (audio, FileTest.EXISTS));
            assert_cmpstr (new Music.LocationSettings (config).load (), CompareOperator.EQ, source_uri);

            var reopened = new Music.Window (app, config, Gst.ElementFactory.make ("fakesink", null), null, cache_path);
            reopened.present ();
            wait_until (() => { return !reopened.loading; });
        show_songs (reopened);
            wait_for_notice (reopened, "No se pudo cargar la biblioteca. Revisá Preferencias.");
            Test.message ("Reopened with unavailable source: %u known tracks", reopened.track_count);
            assert_cmpuint (reopened.track_count, CompareOperator.EQ, 1);
            wait_until (() => { return find_visible_label (find_named (reopened, "tracks"), "song") != null; });
            close_and_flush (reopened);

            File.new_for_path (root + "/audio-offline/song.wav").delete ();
            File.new_for_path (root + "/audio-offline").delete ();
            File.new_for_path (config).delete ();
            FileUtils.unlink (settings + "/session.ini");
            File.new_for_path (settings).delete ();
            var cache_files = File.new_for_path (cache_path).enumerate_children (FileAttribute.STANDARD_NAME, FileQueryInfoFlags.NONE);
            FileInfo? entry;
            while ((entry = cache_files.next_file ()) != null) cache_files.get_child (entry).delete ();
            cache_files.close ();
            File.new_for_path (cache_path).delete ();
            File.new_for_path (root).delete ();
        } catch (Error e) { error ("Fixture de reapertura con caché: %s", e.message); }
    });
    Test.add_func ("/ui/givenCorruptCache_whenWindowOpens_thenLibraryIsRebuiltFromSource", () => {
        try {
            string root = DirUtils.make_tmp ("gtkplayer-ui-corrupt-cache-XXXXXX");
            string audio = root + "/audio";
            string settings = root + "/settings";
            string cache_path = root + "/cache";
            File.new_for_path (audio).make_directory ();
            File.new_for_path (settings).make_directory ();
            string[] command = {"ffmpeg", "-v", "error", "-f", "lavfi", "-i", "sine=duration=0.2", "-y", audio + "/song.wav"};
            int status;
            Process.spawn_sync (null, command, null, SpawnFlags.SEARCH_PATH, null, null, null, out status);
            assert_cmpint (status, CompareOperator.EQ, 0);
            string config = settings + "/settings.ini";
            string source_uri = File.new_for_path (audio).get_uri ();
            string song_uri = File.new_for_path (audio + "/song.wav").get_uri ();
            new Music.LocationSettings (config).save (source_uri);
            var cache = new Music.LibraryCache (cache_path);
            cache.save (source_uri, new Music.Track[] { new Music.Track (song_uri, "song") });
            assert_cmpint (cache.load (source_uri).length, CompareOperator.EQ, 1);
            string cache_file = Path.build_filename (cache_path,
                Checksum.compute_for_string (ChecksumType.SHA256, source_uri) + ".ini");
            // Corrupt only the private cache, before Window starts watching the unchanged source.
            FileUtils.set_contents (cache_file, "[broken cache");

            var window = new Music.Window (application (), config, Gst.ElementFactory.make ("fakesink", null), null, cache_path);
            window.present ();
            wait_until (() => { return !window.loading; });
        show_songs (window);
            assert_cmpuint (window.track_count, CompareOperator.EQ, 1);
            wait_until (() => { return find_visible_label (find_named (window, "tracks"), "song") != null; });
            var rebuilt = new Music.LibraryCache (cache_path).load (source_uri);
            assert_cmpint (rebuilt.length, CompareOperator.EQ, 1);
            assert_cmpstr (rebuilt[0].uri, CompareOperator.EQ, song_uri);
            assert_cmpstr (rebuilt[0].title, CompareOperator.EQ, "song");
            close_and_flush (window);

            File.new_for_path (cache_file).delete ();
            File.new_for_path (cache_path).delete ();
            File.new_for_path (audio + "/song.wav").delete ();
            File.new_for_path (audio).delete ();
            File.new_for_path (config).delete ();
            FileUtils.unlink (settings + "/session.ini");
            File.new_for_path (settings).delete ();
            File.new_for_path (root).delete ();
        } catch (Error e) { error ("Fixture de caché corrupta: %s", e.message); }
    });
    Test.add_func ("/ui/givenCachedLibraryWithUnreadableNestedAlbum_whenAlbumRecoversWithoutRootEvents_thenFallbackRefreshesToTwoTracks", () => {
        try {
            string root = DirUtils.make_tmp ("gtkplayer-ui-nested-recovery-XXXXXX");
            string audio = root + "/audio";
            string album_path = audio + "/artist/album";
            string settings = root + "/settings";
            string cache_path = root + "/cache";
            var source = File.new_for_path (audio);
            var album = File.new_for_path (album_path);
            album.make_directory_with_parents ();
            File.new_for_path (settings).make_directory ();
            string[] command = {"ffmpeg", "-v", "error", "-f", "lavfi", "-i", "sine=duration=0.2", "-y", album_path + "/song.wav"};
            int status;
            Process.spawn_sync (null, command, null, SpawnFlags.SEARCH_PATH, null, null, null, out status);
            assert_cmpint (status, CompareOperator.EQ, 0);
            var song = File.new_for_path (album_path + "/song.wav");
            string config = settings + "/settings.ini";
            string source_uri = source.get_uri ();
            new Music.LocationSettings (config).save (source_uri);
            var cache = new Music.LibraryCache (cache_path);
            cache.save (source_uri, new Music.Track[] { new Music.Track (song.get_uri (), "song") });
            assert_cmpint (cache.load (source_uri).length, CompareOperator.EQ, 1);

            album.set_attribute_uint32 (FileAttribute.UNIX_MODE, 0, FileQueryInfoFlags.NONE);
            bool permission_denied = false;
            try {
                var children = album.enumerate_children (FileAttribute.STANDARD_NAME, FileQueryInfoFlags.NONE);
                children.close ();
            } catch (IOError.PERMISSION_DENIED e) { permission_denied = true; }
            assert (permission_denied);

            // Prove the real root monitor works BEFORE construction, ignoring only this probe.
            int root_events = 0;
            bool probe_seen = false;
            bool probe_deleted = false;
            var probe = source.get_child ("monitor-probe.txt");
            var root_monitor = source.monitor_directory (FileMonitorFlags.WATCH_MOVES);
            root_monitor.changed.connect ((file, other, event) => {
                if (file.equal (probe) || (other != null && other.equal (probe))) {
                    probe_seen = true;
                    if (event == FileMonitorEvent.DELETED) probe_deleted = true;
                } else root_events++;
            });
            var probe_stream = probe.create (FileCreateFlags.NONE);
            size_t written;
            probe_stream.write_all ("probe".data, out written);
            probe_stream.close ();
            wait_until (() => { return probe_seen; });
            probe.delete ();
            wait_until (() => { return probe_deleted; });
            while (MainContext.default ().pending ()) MainContext.default ().iteration (false);
            root_events = 0;

            // All source/settings/cache preparation precedes Window's automatic load.
            var window = new FastRecoveryWindow (application (), config, cache_path);
            window.present ();
            wait_until (() => { return !window.loading; });
        show_songs (window);
            wait_for_notice (window, "No se pudo cargar la biblioteca. Revisá Preferencias.");
            assert_cmpuint (window.track_count, CompareOperator.EQ, 1);
            wait_until (() => { return find_visible_label (find_named (window, "tracks"), "song") != null; });
            assert_cmpint (cache.load (source_uri).length, CompareOperator.EQ, 1);
            assert_cmpint (root_events, CompareOperator.EQ, 0);

            // The failed recursive enumeration never reaches watch_snapshot: only root is watched.
            // Neither this chmod nor this WAV copy touches root's immediate children.
            album.set_attribute_uint32 (FileAttribute.UNIX_MODE, 0755, FileQueryInfoFlags.NONE);
            var second = File.new_for_path (album_path + "/track-two.wav");
            song.copy (second, FileCopyFlags.NONE);
            Test.message ("Root monitor probe observed and drained; Window constructed, loading=%s, tracks=%u, cached=%d, root events=%d; waiting for nested recovery",
                window.loading.to_string (), window.track_count, cache.load (source_uri).length, root_events);
            wait_until (() => { return !window.loading && window.track_count == 2; });
            wait_until (() => { return find_visible_label (find_named (window, "tracks"), "track-two") != null; });
            var stored = cache.load (source_uri);
            assert_cmpint (stored.length, CompareOperator.EQ, 2);
            bool second_cached = false;
            foreach (var track in stored) if (track.uri == second.get_uri ()) second_cached = true;
            assert (second_cached);
            assert_cmpint (root_events, CompareOperator.EQ, 0);
            Test.message ("Nested permissions restored and second WAV discovered without reload or root events; root monitor was proven live before Window construction");
            close_and_flush (window);
            root_monitor.cancel ();

            second.delete ();
            song.delete ();
            album.delete ();
            File.new_for_path (audio + "/artist").delete ();
            source.delete ();
            File.new_for_path (config).delete ();
            FileUtils.unlink (settings + "/session.ini");
            File.new_for_path (settings).delete ();
            var cache_files = File.new_for_path (cache_path).enumerate_children (FileAttribute.STANDARD_NAME, FileQueryInfoFlags.NONE);
            FileInfo? entry;
            while ((entry = cache_files.next_file ()) != null) cache_files.get_child (entry).delete ();
            cache_files.close ();
            File.new_for_path (cache_path).delete ();
            File.new_for_path (root).delete ();
        } catch (Error e) { error ("Fixture de recuperación de álbum anidado: %s", e.message); }
    });
    Test.add_func ("/ui/givenFileChangesInNewSubfolder_whenEventsSettle_thenLibraryRefreshesAutomatically", () => {
        try {
            string root = DirUtils.make_tmp ("gtkplayer-ui-monitor-XXXXXX");
            string audio = root + "/audio";
            string settings = root + "/settings";
            string cache_path = root + "/cache";
            File.new_for_path (audio).make_directory ();
            File.new_for_path (settings).make_directory ();
            File.new_for_path (cache_path).make_directory ();
            string[] command = {"ffmpeg", "-v", "error", "-f", "lavfi", "-i", "sine=duration=0.2", "-y", audio + "/song.wav"};
            int status;
            Process.spawn_sync (null, command, null, SpawnFlags.SEARCH_PATH, null, null, null, out status);
            assert_cmpint (status, CompareOperator.EQ, 0);
            string config = settings + "/settings.ini";
            new Music.LocationSettings (config).save (audio);
            var window = new Music.Window (application (), config, Gst.ElementFactory.make ("fakesink", null), null, cache_path);
            window.present ();
            wait_until (() => { return !window.loading && window.track_count == 1; });
        show_songs (window);

            // One notification per applied snapshot, not per raw filesystem event.
            int publications = 0;
            window.library_updated.connect (() => { publications++; });
            string nested = audio + "/new/subfolder";
            File.new_for_path (nested).make_directory_with_parents ();
            var original = File.new_for_path (audio + "/song.wav");
            original.copy (File.new_for_path (audio + "/new/track-two.wav"), FileCopyFlags.NONE);
            original.copy (File.new_for_path (nested + "/track-three.wav"), FileCopyFlags.NONE);

            Test.message ("Real directory creation and two WAV copies must publish one consolidated snapshot, without reload");
            wait_until (() => { return !window.loading && window.track_count == 3; });
            wait_for_layout (window);
            assert_cmpint (publications, CompareOperator.EQ, 1);
            show_songs (window);
        var tracks = find_media_list (find_named (window, "tracks"));
            assert_nonnull (tracks);
            assert_nonnull (list_item (tracks, 2));
            assert_null (list_item (tracks, 3));
            foreach (string title in new string[] {"song", "track-two", "track-three"}) {
                int matches = 0;
                for (int i = 0; i < 3; i++)
                    if (has_text (list_item (tracks, i), title)) matches++;
                assert_cmpint (matches, CompareOperator.EQ, 1);
            }

            // A later real change proves the newly discovered subfolder stays watched.
            File.new_for_path (nested + "/track-three.wav").delete ();
            Test.message ("Deleting inside the new subfolder must publish the next snapshot automatically");
            wait_until (() => { return !window.loading && window.track_count == 2; });
            wait_for_layout (window);
            assert_cmpint (publications, CompareOperator.EQ, 2);
            assert_nonnull (list_item (tracks, 1));
            assert_null (list_item (tracks, 2));
            assert (has_text (tracks, "song") && has_text (tracks, "track-two"));
            assert (!has_text (tracks, "track-three"));
            close_and_flush (window);

            File.new_for_path (audio + "/new/track-two.wav").delete ();
            File.new_for_path (nested).delete ();
            File.new_for_path (audio + "/new").delete ();
            original.delete ();
            File.new_for_path (audio).delete ();
            File.new_for_path (config).delete ();
            FileUtils.unlink (settings + "/session.ini");
            File.new_for_path (settings).delete ();
            var cache_files = File.new_for_path (cache_path).enumerate_children (FileAttribute.STANDARD_NAME, FileQueryInfoFlags.NONE);
            FileInfo? entry;
            while ((entry = cache_files.next_file ()) != null) cache_files.get_child (entry).delete ();
            cache_files.close ();
            File.new_for_path (cache_path).delete ();
            File.new_for_path (root).delete ();
        } catch (Error e) { error ("Fixture de actualización automática: %s", e.message); }
    });
    Test.add_func ("/ui/givenUnchangedAudioLibrary_whenUnrelatedFileChanges_thenCacheIsNotRewritten", () => {
        try {
            string root = DirUtils.make_tmp ("gtkplayer-ui-unchanged-cache-XXXXXX");
            string audio = root + "/audio";
            string album = audio + "/album";
            string settings = root + "/settings";
            string cache_path = root + "/cache";
            // Discovering this subfolder also exercises the watch-installation follow-up.
            File.new_for_path (album).make_directory_with_parents ();
            File.new_for_path (settings).make_directory ();
            string[] command = {"ffmpeg", "-v", "error", "-f", "lavfi", "-i", "sine=duration=0.2", "-y", album + "/song.wav"};
            int status;
            Process.spawn_sync (null, command, null, SpawnFlags.SEARCH_PATH, null, null, null, out status);
            assert_cmpint (status, CompareOperator.EQ, 0);
            string config = settings + "/settings.ini";
            string source_uri = File.new_for_path (audio).get_uri ();
            string song_uri = File.new_for_path (album + "/song.wav").get_uri ();
            new Music.LocationSettings (config).save (source_uri);
            var window = new Music.Window (application (), config, Gst.ElementFactory.make ("fakesink", null), null, cache_path);
            int started = 0;
            int completed = 0;
            window.notify["loading"].connect (() => {
                if (window.loading) started++;
                else completed++;
            });
            window.present ();
            // Both completions include cache I/O: no initial or topology write remains.
            wait_until (() => { return completed >= 2 && !window.loading; });
        show_songs (window);
            assert_cmpuint (window.track_count, CompareOperator.EQ, 1);
            assert_cmpint (new Music.LibraryCache (cache_path).load (source_uri).length, CompareOperator.EQ, 1);
            Test.message ("Initial load and topology follow-up completed before recording cache metadata");

            // Locate only this fixture's cache, without depending on its filename or format.
            var files = File.new_for_path (cache_path).enumerate_children (FileAttribute.STANDARD_NAME, FileQueryInfoFlags.NONE);
            var entry = files.next_file ();
            assert_nonnull (entry);
            var cache_file = files.get_child (entry);
            assert_null (files.next_file ());
            files.close ();
            // An old timestamp detects even a same-content rewrite within one clock tick.
            cache_file.set_attribute_uint64 (FileAttribute.TIME_MODIFIED, 946684800, FileQueryInfoFlags.NONE);
            uint64 before = cache_file.query_info (FileAttribute.TIME_MODIFIED, FileQueryInfoFlags.NONE)
                .get_attribute_uint64 (FileAttribute.TIME_MODIFIED);
            assert (before == 946684800);
            started = completed = 0;
            int publications = 0;
            window.library_updated.connect (() => { publications++; });

            FileUtils.set_contents (audio + "/notes.txt", "No audio changed.\n");
            // The real monitor must cause a complete loading cycle; elapsed time is not evidence.
            wait_until (() => { return started > 0; });
            wait_until (() => { return completed > 0 && !window.loading; });
            uint64 after = cache_file.query_info (FileAttribute.TIME_MODIFIED, FileQueryInfoFlags.NONE)
                .get_attribute_uint64 (FileAttribute.TIME_MODIFIED);
            var stored = new Music.LibraryCache (cache_path).load (source_uri);
            assert_cmpint (stored.length, CompareOperator.EQ, 1);
            assert_cmpstr (stored[0].uri, CompareOperator.EQ, song_uri);
            assert_cmpstr (stored[0].title, CompareOperator.EQ, "song");
            assert_cmpuint (window.track_count, CompareOperator.EQ, 1);
            assert_cmpint (publications, CompareOperator.EQ, 0);
            Test.message ("Unrelated file reconciled: loading starts=%d, completions=%d, publications=%d, cache mtime before=%" + uint64.FORMAT + ", after=%" + uint64.FORMAT,
                started, completed, publications, before, after);
            assert (after == before);
            close_and_flush (window);

            File.new_for_path (audio + "/notes.txt").delete ();
            File.new_for_path (album + "/song.wav").delete ();
            File.new_for_path (album).delete ();
            File.new_for_path (audio).delete ();
            File.new_for_path (config).delete ();
            FileUtils.unlink (settings + "/session.ini");
            File.new_for_path (settings).delete ();
            cache_file.delete ();
            File.new_for_path (cache_path).delete ();
            File.new_for_path (root).delete ();
        } catch (Error e) { error ("Fixture de caché sin cambios de audio: %s", e.message); }
    });
    Test.add_func ("/ui/givenPendingFilesystemChanges_whenWindowCloses_thenNoBackgroundSnapshotIsPublished", () => {
        try {
            string root = DirUtils.make_tmp ("gtkplayer-ui-close-pending-XXXXXX");
            string audio = root + "/audio";
            string settings = root + "/settings";
            string cache_path = root + "/cache";
            File.new_for_path (audio).make_directory ();
            File.new_for_path (settings).make_directory ();
            string[] command = {"ffmpeg", "-v", "error", "-f", "lavfi", "-i", "sine=duration=0.2", "-y", audio + "/song.wav"};
            int status;
            Process.spawn_sync (null, command, null, SpawnFlags.SEARCH_PATH, null, null, null, out status);
            assert_cmpint (status, CompareOperator.EQ, 0);
            string config = settings + "/settings.ini";
            string source_uri = File.new_for_path (audio).get_uri ();
            new Music.LocationSettings (config).save (source_uri);
            var window = new Music.Window (application (), config, Gst.ElementFactory.make ("fakesink", null), null, cache_path);
            window.present ();
            wait_until (() => { return !window.loading && window.track_count == 1; });
        show_songs (window);
            assert_cmpint (new Music.LibraryCache (cache_path).load (source_uri).length, CompareOperator.EQ, 1);

            int publications = 0;
            int loading_changes = 0;
            window.library_updated.connect (() => { publications++; });
            window.notify["loading"].connect (() => { loading_changes++; });
            // Allow an initial watch-installation follow-up to finish before the scenario.
            var settling = new MainLoop ();
            Timeout.add (1700, () => { settling.quit (); return Source.REMOVE; });
            settling.run ();
            wait_until (() => { return !window.loading; });
            assert_cmpint (new Music.LibraryCache (cache_path).load (source_uri).length, CompareOperator.EQ, 1);
            publications = 0;
            loading_changes = 0;

            int64 changed_at = get_monotonic_time ();
            File.new_for_path (audio + "/song.wav").copy (File.new_for_path (audio + "/track-two.wav"), FileCopyFlags.NONE);
            // Dispatch filesystem events, but close well before the 1500 ms debounce.
            var dispatch = new MainLoop ();
            Timeout.add (100, () => { dispatch.quit (); return Source.REMOVE; });
            dispatch.run ();
            assert (get_monotonic_time () - changed_at < 1500 * TimeSpan.MILLISECOND);
            assert (!window.loading);
            assert_cmpint (publications, CompareOperator.EQ, 0);
            assert_cmpint (loading_changes, CompareOperator.EQ, 0);
            close_and_flush (window);

            // Absence is observed over a full interval, never an immediately true predicate.
            var observation = new MainLoop ();
            Timeout.add (2000, () => { observation.quit (); return Source.REMOVE; });
            observation.run ();
            assert_cmpint (publications, CompareOperator.EQ, 0);
            assert_cmpint (loading_changes, CompareOperator.EQ, 0);
            var stored = new Music.LibraryCache (cache_path).load (source_uri);
            assert_cmpint (stored.length, CompareOperator.EQ, 1);
            assert_cmpstr (stored[0].uri, CompareOperator.EQ, File.new_for_path (audio + "/song.wav").get_uri ());
            Test.message ("Closed before debounce: no publication or loading notification over 2000 ms; cache retains one track");

            File.new_for_path (audio + "/track-two.wav").delete ();
            File.new_for_path (audio + "/song.wav").delete ();
            File.new_for_path (audio).delete ();
            File.new_for_path (config).delete ();
            FileUtils.unlink (settings + "/session.ini");
            File.new_for_path (settings).delete ();
            var cache_files = File.new_for_path (cache_path).enumerate_children (FileAttribute.STANDARD_NAME, FileQueryInfoFlags.NONE);
            FileInfo? entry;
            while ((entry = cache_files.next_file ()) != null) cache_files.get_child (entry).delete ();
            cache_files.close ();
            File.new_for_path (cache_path).delete ();
            File.new_for_path (root).delete ();
        } catch (Error e) { error ("Fixture de cierre con cambios pendientes: %s", e.message); }
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
        show_songs (window);
        show_songs (window);
        var tracks = find_media_list (find_named (window, "tracks"));
        var queue = find_media_list (find_named (window, "details"));
        var title = (Gtk.Label) find_named (window, "now-playing");
        var play = find_play (window);
        assert (tracks.single_click_activate);
        assert (queue.single_click_activate);
        assert (!has_text (window, "Doble clic"));
        // Native row activation is also the keyboard path; this is not a physical pointer test.
        ((Gtk.SingleSelection) tracks.model).selected = 1;
        tracks.activate (1);
        wait_until (() => { return title.label.has_prefix ("track-two\n") && play.icon_name == "media-playback-pause-symbolic"; });
        assert (selected_index (tracks) == 1);
        assert (selected_index (queue) == 0);
        assert (queue.model.get_n_items () == 1);
        tracks.activate (0);
        wait_until (() => { return title.label.has_prefix ("song\n"); });
        assert (queue.model.get_n_items () == 2);
        assert (has_text (find_named (window, "details"), "track-two"));
        ((Gtk.SingleSelection) queue.model).selected = 1;
        queue.activate (1);
        wait_until (() => { return title.label.has_prefix ("song\n") && play.icon_name == "media-playback-pause-symbolic"; });
        assert (selected_index (queue) == 1 && queue.model.get_n_items () == 2);
        close_and_flush (window);
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
        show_songs (window);
        var bar = find_named (window, "controls");
        var play = find_play (bar);
        var previous = (Gtk.Button) play.get_parent ().get_first_child ();
        var next = (Gtk.Button) play.get_next_sibling ();
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
        close_and_flush (window);
        remove_fixture (empty);
        remove_fixture (populated);
    });
    Test.add_func ("/ui/empty-library-queue-and-load-failure-guidance", () => {
        string folder = fixture ();
        assert (FileUtils.unlink (folder + "/song.wav") == 0);
        var window = new Music.Window (application (), folder + "/settings.ini", Gst.ElementFactory.make ("fakesink", null));
        window.present ();
        wait_until (() => { return !window.loading; });
        show_songs (window);
        var center = find_named (window, "tracks");
        assert (has_text (center, "Biblioteca vacía"));
        assert (has_text (center, "Elegí una ubicación con música en Preferencias"));
        assert (!has_text (center, "Seleccioná un álbum"));
        var preferences = open_preferences (window);
        assert (has_text (preferences, "0 pistas cargadas · 0 archivos de audio omitidos"));
        preferences.close ();
        var stack = (Gtk.Stack) find_media_list (find_named (window, "details")).get_ancestor (typeof (Gtk.Stack));
        stack.visible_child_name = "queue";
        wait_for_layout (stack);
        var placeholder = find_named (window, "queue-empty");
        assert (placeholder is Adw.StatusPage && placeholder.get_mapped ());
        assert (has_text (placeholder, "Cola vacía"));
        assert (has_text (placeholder, "Agregá música desde la biblioteca"));
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
        close_and_flush (window);
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
        show_songs (window);
        var groups = find_list (find_named (window, "library"));
        show_songs (window);
        var tracks = find_media_list (find_named (window, "tracks"));
        var play = find_play (window);
        var previous = (Gtk.Button) play.get_parent ().get_first_child ();
        var next = (Gtk.Button) play.get_next_sibling ();
        // Filter to the original WAV's album, leaving one playable visible track.
        select_album (find_named (window, "library"), "Artista desconocido", "Sin álbum");
        assert (list_item (tracks, 1) == null);
        assert (has_text (find_named (window, "tracks"), "Sin álbum — Artista desconocido · 1 pista"));
        assert (play.sensitive && !previous.sensitive && !next.sensitive);
        tracks.activate (0);
        wait_until (() => { return play.icon_name == "media-playback-pause-symbolic"; });
        groups.select_row (groups.get_row_at_index (2));
        assert (list_item (tracks, 1) != null);
        // The active queue is still the single-track selection, not the newly visible group.
        assert (play.sensitive && !previous.sensitive && !next.sensitive);
        window.load_library.begin (empty);
        wait_until (() => { return !window.loading && window.track_count == 0; });
        assert (list_item (tracks, 0) == null);
        assert (play.sensitive && !previous.sensitive && !next.sensitive);
        assert (has_text (find_named (window, "controls"), "song\n"));
        play.clicked ();
        wait_until (() => { return play.icon_name == "media-playback-start-symbolic"; });
        assert (play.sensitive);
        play.clicked ();
        wait_until (() => { return play.icon_name == "media-playback-pause-symbolic"; });
        assert (has_text (find_named (window, "controls"), "song\n"));
        close_and_flush (window);
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
        show_songs (window);
        var play = find_play (window);
        var previous = (Gtk.Button) play.get_parent ().get_first_child ();
        var next = (Gtk.Button) play.get_next_sibling ();
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
        assert (selected_index (find_media_list (find_named (window, "details"))) == 1);
        close_and_flush (window);
        FileUtils.unlink (folder + "/track-two.wav");
        remove_fixture (folder);
    });
    Test.add_func ("/ui/artist-navigation-opens-albums", () => {
        string folder = fixture ();
        try {
            string[] command = {"ffmpeg", "-v", "error", "-i", folder + "/song.wav",
                "-metadata", "artist=Banda de prueba", "-metadata", "album=Primer álbum",
                "-y", folder + "/album.flac"};
            int status;
            Process.spawn_sync (null, command, null, SpawnFlags.SEARCH_PATH, null, null, null, out status);
            assert (status == 0);
        } catch (Error e) { error ("%s", e.message); }
        assert (FileUtils.unlink (folder + "/song.wav") == 0);
        var window = new Music.Window (application (), folder + "/settings.ini", Gst.ElementFactory.make ("fakesink", null));
        window.present ();
        wait_until (() => { return !window.loading && window.track_count == 1; });
        var library = find_named (window, "library");
        var modes = find_list (library);
        modes.select_row (modes.get_row_at_index (1));
        var artists = (Gtk.ListView) find_named (window, "artist-list");
        wait_for_layout (window);
        assert (artists.model.get_n_items () == 1);
        assert (((Music.LibraryGroup) artists.model.get_item (0)).title == "Banda de prueba");
        artists.activate (0);
        var grid = (Gtk.GridView) find_named (window, "album-grid");
        wait_for_layout (window);
        assert (grid.get_mapped () && grid.model.get_n_items () == 1);
        assert (((Music.LibraryGroup) grid.model.get_item (0)).title == "Primer álbum");
        close_and_flush (window);
        FileUtils.unlink (folder + "/album.flac");
        remove_fixture (folder);
    });
    Test.add_func ("/ui/unicode-artists-have-distinct-album-models", () => {
        string folder = fixture ();
        string[] artists = {"Café", "Cafe\u0301", "Café"};
        string[] albums = {"A", "B", "C"};
        for (int i = 0; i < albums.length; i++) {
            try {
                string[] command = {"ffmpeg", "-v", "error", "-i", folder + "/song.wav",
                    "-metadata", "artist=" + artists[i], "-metadata", "album=" + albums[i],
                    "-y", folder + "/unicode%d.flac".printf (i)};
                int status;
                Process.spawn_sync (null, command, null, SpawnFlags.SEARCH_PATH, null, null, null, out status);
                assert (status == 0);
            } catch (Error e) { error ("%s", e.message); }
        }
        assert (FileUtils.unlink (folder + "/song.wav") == 0);
        var window = new Music.Window (application (), folder + "/settings.ini", Gst.ElementFactory.make ("fakesink", null));
        window.present ();
        wait_until (() => { return !window.loading && window.track_count == 3; });
        var modes = find_list (find_named (window, "library"));
        modes.select_row (modes.get_row_at_index (1));
        var artist_view = (Gtk.ListView) find_named (window, "artist-list");
        assert (artist_view.model.get_n_items () == 2);
        for (uint j = 0; j < artist_view.model.get_n_items (); j++) {
            var artist = (Music.LibraryGroup) artist_view.model.get_item (j);
            assert (artist.tracks.length == (artist.title == artists[0] ? 2 : 1));
            artist_view.activate (j);
            var grid = (Gtk.GridView) find_named (window, "album-grid");
            assert (grid.model.get_n_items () == artist.tracks.length);
            for (uint k = 0; k < grid.model.get_n_items (); k++)
                assert (((Music.LibraryGroup) grid.model.get_item (k)).artist == artist.title);
        }
        close_and_flush (window);
        for (int i = 0; i < albums.length; i++) FileUtils.unlink (folder + "/unicode%d.flac".printf (i));
        remove_fixture (folder);
    });
    Test.add_func ("/ui/homonymous-albums-select-exact-artist", () => {
        string folder = fixture ();
        string[] artists = {"Artista A", "Artista B", "Artista B"};
        string[] albums = {"Compartido", "Compartido", "Otro álbum"};
        string[] titles = {"Pista de A", "Pista de B compartida", "Pista de B distinta"};
        for (int i = 0; i < titles.length; i++) {
            try {
                string[] command = {"ffmpeg", "-v", "error", "-i", folder + "/song.wav",
                    "-metadata", "artist=" + artists[i], "-metadata", "album=" + albums[i],
                    "-metadata", "title=" + titles[i], "-y", folder + "/track%d.flac".printf (i)};
                int status;
                Process.spawn_sync (null, command, null, SpawnFlags.SEARCH_PATH, null, null, null, out status);
                assert (status == 0);
            } catch (Error e) { error ("%s", e.message); }
        }
        assert (FileUtils.unlink (folder + "/song.wav") == 0);
        var window = new Music.Window (application (), folder + "/settings.ini", Gst.ElementFactory.make ("fakesink", null));
        window.present ();
        wait_until (() => { return !window.loading && window.track_count == 3; });
        show_songs (window);
        var library = find_named (window, "library");
        show_songs (window);
        var tracks = find_media_list (find_named (window, "tracks"));
        assert (tracks != null);
        for (int i = 0; i < titles.length; i++) {
            select_album (library, artists[i], albums[i]);
            Test.message ("Selected %s / %s: only %s must appear", artists[i], albums[i], titles[i]);
            assert (list_item (tracks, 0) != null);
            assert (list_item (tracks, 1) == null);
            assert (has_text (list_item (tracks, 0), artists[i]));
            for (int j = 0; j < titles.length; j++)
                assert (has_text (tracks, titles[j]) == (i == j));
        }
        var groups = find_list (library);
        assert (groups != null && has_text (groups.get_row_at_index (2), "Canciones"));
        groups.select_row (groups.get_row_at_index (2));
        wait_for_layout (window);
        assert (list_item (tracks, 2) != null && list_item (tracks, 3) == null);
        foreach (var title in titles) assert (has_text (tracks, title));
        close_and_flush (window);
        for (int i = 0; i < titles.length; i++) FileUtils.unlink (folder + "/track%d.flac".printf (i));
        remove_fixture (folder);
    });
    Test.add_func ("/ui/givenAlbumSelected_whenPublicArtistPortraitLoads_thenShowsPortraitAndAttributionWithoutReplacingAlbumCover", () => {
        string folder = fixture ("8");
        var server = new Soup.Server ("server-header", "ui-artist-photo-fixture", null);
        try {
            // A large red album cover cannot be mistaken for the 16×16 portrait.
            var artwork = new Gdk.Pixbuf (Gdk.Colorspace.RGB, false, 8, 320, 320);
            artwork.fill (0xd43b32ffU);
            artwork.save (folder + "/cover.jpg", "jpeg");
            string[] command = {"ffmpeg", "-v", "error", "-i", folder + "/song.wav",
                "-metadata", "artist=Nina Simone", "-metadata", "album=Álbum de prueba",
                "-metadata", "title=Pista de prueba", "-y", folder + "/album.flac"};
            int status;
            Process.spawn_sync (null, command, null, SpawnFlags.SEARCH_PATH, null, null, null, out status);
            assert (status == 0);
            assert (FileUtils.unlink (folder + "/song.wav") == 0);
            var jpeg = new Bytes (Base64.decode (
                "/9j/4AAQSkZJRgABAgAAAQABAAD//gAQTGF2YzYyLjExLjEwMAD/2wBDAAgEBAQEBAUFBQUFBQYGBgYGBgYGBgYGBgYHBwcICAgHBwcGBgcHCAgICAkJCQgICAgJCQoKCgwMCwsODg4RERT/xABMAAEBAAAAAAAAAAAAAAAAAAAABwEBAQAAAAAAAAAAAAAAAAAABQcQAQAAAAAAAAAAAAAAAAAAAAARAQAAAAAAAAAAAAAAAAAAAAD/wAARCAAQABADASIAAhEAAxEA/9oADAMBAAIRAxEAPwCOAL+Kf//Z"));
            server.listen_local (0, Soup.ServerListenOptions.IPV4_ONLY);
            string uri = server.get_uris ().data.to_string ();
            string origin = uri.substring (0, uri.length - 1);
            server.add_handler (null, (local, message, path, query) => {
                string body;
                switch (path) {
                case "/api/rest_v1/page/summary/Nina Simone":
                    body = """{"type":"standard","title":"Nina Simone","description":"American singer and pianist","thumbnail":{"source":"%s/portrait.jpg"},"originalimage":{"source":"%s/original/Portrait.jpg"}}""".printf (origin, origin);
                    break;
                case "/w/api.php":
                    body = """{"query":{"pages":{"123":{"pageid":123,"ns":6,"title":"File:Portrait.jpg","imageinfo":[{"url":"%s/original/Portrait.jpg","thumburl":"%s/portrait.jpg","descriptionurl":"%s/wiki/File:Portrait.jpg","extmetadata":{"Artist":{"value":"<a href=\"https://example.org/photographer\">Example &lt;Photographer&gt;</a>"},"LicenseShortName":{"value":"CC BY-SA 4.0"},"LicenseUrl":{"value":"https://creativecommons.org/licenses/by-sa/4.0/"}}}]}}}}""".printf (origin, origin, origin);
                    break;
                case "/portrait.jpg":
                    message.set_status (200, null);
                    message.set_response ("image/jpeg", Soup.MemoryUse.COPY, jpeg.get_data ());
                    return;
                default:
                    message.set_status (404, null);
                    return;
                }
                message.set_status (200, null);
                message.set_response ("application/json", Soup.MemoryUse.COPY, body.data);
            });
            var photos = new Music.ArtistPhotos.for_test_server (origin);
            var sink = Gst.ElementFactory.make ("fakesink", null);
            sink.set ("sync", true);
            Music.Window window = new Music.Window (application (), folder + "/settings.ini", sink, photos);
            window.present ();
            wait_until (() => { return !window.loading && window.track_count == 1; });
            select_album (find_named (window, "library"), "Nina Simone", "Álbum de prueba");
            var summary = find_named (window, "tracks").get_first_child ();
            Gtk.Image? cover = summary.get_first_child () as Gtk.Image;
            assert (cover != null);
            Gdk.Texture? cover_texture = cover.get_paintable () as Gdk.Texture;
            assert_nonnull (cover_texture);
            assert (cover_texture.get_width () == 320 && cover_texture.get_height () == 320);
            var details = find_named (window, "details");
            ((Gtk.Stack) find_media_list (details).get_ancestor (typeof (Gtk.Stack))).visible_child_name = "data";
            wait_for_layout (window);
            Gtk.Widget? portrait = null;
            wait_until (() => {
                portrait = find_named (details, "artist-portrait");
                if (portrait is Gtk.Image) return ((Gtk.Image) portrait).get_paintable () is Gdk.Texture;
                if (portrait is Gtk.Picture) return ((Gtk.Picture) portrait).paintable is Gdk.Texture;
                return false;
            });
            wait_for_layout (window);
            Gdk.Paintable? portrait_paintable = null;
            if (portrait is Gtk.Image) portrait_paintable = ((Gtk.Image) portrait).get_paintable ();
            else portrait_paintable = ((Gtk.Picture) portrait).paintable;
            var portrait_texture = (Gdk.Texture) portrait_paintable;
            assert (portrait_texture.get_width () == 16 && portrait_texture.get_height () == 16);
            assert (portrait.get_mapped ());
            assert (portrait.get_width () > 0 && portrait.get_width () <= 320);
            assert (portrait.get_height () > 0 && portrait.get_height () <= 320);
            assert (find_visible_label (details, "Nina Simone") != null);
            var author = find_visible_label (details, "Example <Photographer>");
            assert (author != null && !author.use_markup);
            var license = find_visible_link (details, "https://creativecommons.org/licenses/by-sa/4.0/");
            var source = find_visible_link (details, origin + "/wiki/File:Portrait.jpg");
            assert (license != null && license.sensitive && license.label.contains ("CC BY-SA 4.0"));
            assert (source != null && source.sensitive && source.label.strip () != "");
            assert (cover.get_paintable () == cover_texture && cover.get_mapped ());
            assert (has_text (summary, "Álbum de prueba"));

            var tracks = find_media_list (find_named (window, "tracks"));
            tracks.activate (0);
            wait_until (() => { return find_play (window).icon_name == "media-playback-pause-symbolic"; });
            assert (has_text (find_named (window, "controls"), "Pista de prueba"));
            assert (find_visible_label (details, "Pista de prueba") != null);
            assert (find_visible_label (details, "Artista:") != null);
            assert (find_visible_label (details, "Álbum de prueba") != null);
            assert (portrait.get_mapped () && author.get_mapped () && license.get_mapped () && source.get_mapped ());
            assert (cover.get_paintable () == cover_texture && cover.get_mapped ());
            close_and_flush (window);
        } catch (Error e) { error ("Retrato en Datos: %s", e.message); }
        server.disconnect ();
        FileUtils.unlink (folder + "/album.flac");
        FileUtils.unlink (folder + "/cover.jpg");
        remove_fixture (folder);
    });
    Test.add_func ("/ui/givenArtistPhotoLoading_whenAnotherArtistSelectedAndDownloadFails_thenPreviousPortraitAndCreditsDoNotReappear", () => {
        string folder = fixture ("8");
        var server = new Soup.Server ("server-header", "ui-delayed-portrait-fixture", null);
        try {
            string[] artists = {"Nina Simone", "Aretha Franklin"};
            for (int i = 0; i < artists.length; i++) {
                string[] command = {"ffmpeg", "-v", "error", "-i", folder + "/song.wav",
                    "-metadata", "artist=" + artists[i], "-metadata", "album=Álbum de prueba",
                    "-metadata", "title=Pista de " + artists[i], "-y", folder + "/artist%d.flac".printf (i)};
                int status;
                Process.spawn_sync (null, command, null, SpawnFlags.SEARCH_PATH, null, null, null, out status);
                assert (status == 0);
            }
            assert (FileUtils.unlink (folder + "/song.wav") == 0);
            var jpeg = new Bytes (Base64.decode (
                "/9j/4AAQSkZJRgABAgAAAQABAAD//gAQTGF2YzYyLjExLjEwMAD/2wBDAAgEBAQEBAUFBQUFBQYGBgYGBgYGBgYGBgYGBgYHBwcICAgHBwcGBgcHCAgICAkJCQgICAgJCQoKCgwMCwsODg4RERT/xABMAAEBAAAAAAAAAAAAAAAAAAAABwEBAQAAAAAAAAAAAAAAAAAABQcQAQAAAAAAAAAAAAAAAAAAAAARAQAAAAAAAAAAAAAAAAAAAAD/wAARCAAQABADASIAAhEAAxEA/9oADAMBAAIRAxEAPwCOAL+Kf//Z"));
            server.listen_local (0, Soup.ServerListenOptions.IPV4_ONLY);
            string uri = server.get_uris ().data.to_string ();
            string origin = uri.substring (0, uri.length - 1);
            Soup.ServerMessage? delayed = null;
            bool failed_download = false;
            server.add_handler (null, (local, message, path, query) => {
                string body;
                if (path.has_prefix ("/api/rest_v1/page/summary/")) {
                    string artist = path.has_suffix (artists[0]) ? artists[0] : artists[1];
                    string file = artist == artists[0] ? "PortraitA.jpg" : "PortraitB.jpg";
                    body = """{"type":"standard","title":"%s","description":"Musician","thumbnail":{"source":"%s/%s"},"originalimage":{"source":"%s/original/%s"}}""".printf (artist, origin, file, origin, file);
                } else if (path == "/w/api.php") {
                    string file = query.lookup ("titles") == "File:PortraitA.jpg" ? "PortraitA.jpg" : "PortraitB.jpg";
                    body = """{"query":{"pages":{"123":{"pageid":123,"ns":6,"title":"File:%s","imageinfo":[{"thumburl":"%s/%s","descriptionurl":"%s/wiki/File:%s","extmetadata":{"Artist":{"value":"Fotógrafo de A"},"LicenseShortName":{"value":"CC BY-SA 4.0"},"LicenseUrl":{"value":"https://creativecommons.org/licenses/by-sa/4.0/"}}}]}}}}""".printf (file, origin, file, origin, file);
                } else if (path == "/PortraitA.jpg") {
                    message.set_status (200, null);
                    message.set_response ("image/jpeg", Soup.MemoryUse.COPY, jpeg.get_data ());
                    message.pause ();
                    delayed = message;
                    return;
                } else {
                    message.set_status (503, null);
                    if (path == "/PortraitB.jpg") failed_download = true;
                    return;
                }
                message.set_status (200, null);
                message.set_response ("application/json", Soup.MemoryUse.COPY, body.data);
            });
            var sink = Gst.ElementFactory.make ("fakesink", null);
            sink.set ("sync", true);
            var window = new Music.Window (application (), folder + "/settings.ini", sink,
                new Music.ArtistPhotos.for_test_server (origin));
            window.present ();
            wait_until (() => { return !window.loading && window.track_count == 2; });
        show_songs (window);
            var library = find_named (window, "library");
            var details = find_named (window, "details");
            ((Gtk.Stack) find_media_list (details).get_ancestor (typeof (Gtk.Stack))).visible_child_name = "data";
            wait_for_layout (window);
            select_album (library, artists[0], "Álbum de prueba");
            wait_until (() => { return delayed != null; });
            assert (find_visible_label (details, "Buscando retrato público") != null);

            select_album (library, artists[1], "Álbum de prueba");
            assert (find_visible_label (details, artists[1]) != null);
            delayed.unpause ();
            wait_until (() => {
                return failed_download && find_visible_label (details, "No se pudo cargar el retrato") != null;
            });
            // Give queued responses and rendering a bounded opportunity to surface stale content.
            bool settled = false;
            Timeout.add (150, () => { settled = true; return Source.REMOVE; });
            wait_until (() => { return settled; });
            wait_for_layout (window);
            var portrait = find_named (details, "artist-portrait") as Gtk.Image;
            assert (portrait != null && portrait.get_mapped ());
            assert (portrait.get_paintable () == null);
            assert (portrait.storage_type == Gtk.ImageType.ICON_NAME);
            assert (portrait.icon_name == "avatar-default-symbolic");
            assert (find_visible_label (details, artists[1]) != null);
            assert (find_visible_label (details, artists[0]) == null);
            assert (find_visible_label (details, "Fotógrafo de A") == null);
            for (var child = portrait.get_parent ().get_first_child (); child != null; child = child.get_next_sibling ()) {
                if (child is Gtk.LinkButton) assert (!child.get_mapped () && !child.visible);
            }
            find_media_list (find_named (window, "tracks")).activate (0);
            wait_until (() => { return find_play (window).icon_name == "media-playback-pause-symbolic"; });
            assert (has_text (find_named (window, "controls"), "Pista de " + artists[1]));
            assert (window.get_mapped () && window.sensitive);
            assert (portrait.get_paintable () == null);
            assert (find_visible_label (details, "Fotógrafo de A") == null);
            Test.message ("A's JPEG released after selecting B; B's JPEG returned HTTP 503; B keeps neutral portrait, no credits, and plays");
            close_and_flush (window);
        } catch (Error e) { error ("Cambio de artista durante descarga: %s", e.message); }
        server.disconnect ();
        for (int i = 0; i < 2; i++) FileUtils.unlink (folder + "/artist%d.flac".printf (i));
        remove_fixture (folder);
    });
    Test.add_func ("/ui/givenAlbumWithEmbeddedCover_whenAlbumSelected_thenSummaryShowsBoundedCoverTexture", () => {
        string folder = fixture ();
        try {
            var artwork = new Gdk.Pixbuf (Gdk.Colorspace.RGB, false, 8, 320, 320);
            artwork.fill (0xd43b32ffU);
            artwork.save (folder + "/embedded.png", "png");
            string[] command = {"ffmpeg", "-v", "error", "-i", folder + "/song.wav",
                "-i", folder + "/embedded.png", "-map", "0:a", "-map", "1:v",
                "-c:a", "flac", "-c:v", "copy", "-disposition:v", "attached_pic",
                "-metadata", "album=Álbum con carátula", "-metadata", "artist=Artista de prueba",
                "-y", folder + "/album.flac"};
            int status;
            Process.spawn_sync (null, command, null, SpawnFlags.SEARCH_PATH, null, null, null, out status);
            assert (status == 0);
        } catch (Error e) { error ("%s", e.message); }
        assert (FileUtils.unlink (folder + "/song.wav") == 0);
        // Only embedded artwork remains available to the real metadata scanner.
        assert (FileUtils.unlink (folder + "/embedded.png") == 0);
        var window = new Music.Window (application (), folder + "/settings.ini", Gst.ElementFactory.make ("fakesink", null));
        window.present ();
        wait_until (() => { return !window.loading && window.track_count == 1; });
        show_songs (window);
        var library = find_named (window, "library");
        select_album (library, "Artista de prueba", "Álbum con carátula");
        var center = find_named (window, "tracks");
        var summary = center.get_first_child ();
        assert (has_text (summary, "Álbum con carátula"));
        var cover = summary.get_first_child () as Gtk.Image;
        assert (cover != null);
        wait_for_layout (window);
        Test.message ("Selected album summary: image storage=%s, size=%dx%d",
            cover.storage_type.to_string (), cover.get_width (), cover.get_height ());
        assert (cover.get_paintable () is Gdk.Texture);
        var texture = (Gdk.Texture) cover.get_paintable ();
        assert (texture.get_width () == 320 && texture.get_height () == 320);
        assert (cover.get_mapped ());
        assert (cover.get_width () > 0 && cover.get_width () <= 192);
        assert (cover.get_height () > 0 && cover.get_height () <= 192);
        close_and_flush (window);
        FileUtils.unlink (folder + "/album.flac");
        remove_fixture (folder);
    });
    Test.add_func ("/ui/givenAlbumWithoutEmbeddedArtWithCoverJpg_whenAlbumSelected_thenSummaryShowsBoundedCoverTexture", () => {
        string folder = fixture ();
        try {
            // The WAV contains audio only; its neighbouring JPEG is the only artwork.
            string[] command = {"ffmpeg", "-v", "error", "-f", "lavfi", "-i",
                "color=c=red:s=320x320", "-frames:v", "1", "-threads", "1",
                folder + "/cover.jpg"};
            int status;
            Process.spawn_sync (null, command, null, SpawnFlags.SEARCH_PATH, null, null, null, out status);
            assert (status == 0);
            var artwork = new Gdk.Pixbuf.from_file (folder + "/cover.jpg");
            assert (artwork.width == 320 && artwork.height == 320);
        } catch (Error e) { error ("%s", e.message); }
        var window = new Music.Window (application (), folder + "/settings.ini", Gst.ElementFactory.make ("fakesink", null));
        window.present ();
        wait_until (() => { return !window.loading && window.track_count == 1; });
        show_songs (window);
        var library = find_named (window, "library");
        select_album (library, "Artista desconocido", "Sin álbum");
        var center = find_named (window, "tracks");
        var summary = center.get_first_child ();
        assert (has_text (summary, "Sin álbum"));
        var cover = summary.get_first_child () as Gtk.Image;
        assert (cover != null);
        wait_for_layout (window);
        Test.message ("Selected album with cover.jpg: image storage=%s, size=%dx%d",
            cover.storage_type.to_string (), cover.get_width (), cover.get_height ());
        assert (cover.get_paintable () is Gdk.Texture);
        var texture = (Gdk.Texture) cover.get_paintable ();
        assert (texture.get_width () == 320 && texture.get_height () == 320);
        assert (cover.get_mapped ());
        assert (cover.get_width () > 0 && cover.get_width () <= 192);
        assert (cover.get_height () > 0 && cover.get_height () <= 192);
        close_and_flush (window);
    });
    Test.add_func ("/ui/givenAudioWithoutEmbeddedArtAndExternalCoverSymlink_whenScannedAndAlbumSelected_thenTrackRemainsWithPlaceholder", () => {
        string folder = fixture ();
        string external = "";
        try {
            external = DirUtils.make_tmp ("gtkplayer-external-cover-XXXXXX");
            string[] command = {"ffmpeg", "-v", "error", "-f", "lavfi", "-i",
                "color=c=red:s=320x320", "-frames:v", "1", "-threads", "1",
                external + "/artwork.jpg"};
            int status;
            Process.spawn_sync (null, command, null, SpawnFlags.SEARCH_PATH, null, null, null, out status);
            assert (status == 0);
            var artwork = new Gdk.Pixbuf.from_file (external + "/artwork.jpg");
            assert (artwork.width == 320 && artwork.height == 320);
            File.new_for_path (folder + "/cover.jpg").make_symbolic_link (external + "/artwork.jpg");
            assert (FileUtils.test (folder + "/cover.jpg", FileTest.IS_SYMLINK));
        } catch (Error e) { error ("%s", e.message); }
        var window = new Music.Window (application (), folder + "/settings.ini", Gst.ElementFactory.make ("fakesink", null));
        window.present ();
        wait_until (() => { return !window.loading && window.track_count == 1; });
        show_songs (window);
        var library = find_named (window, "library");
        select_album (library, "Artista desconocido", "Sin álbum");
        var summary = find_named (window, "tracks").get_first_child ();
        assert (has_text (summary, "Sin álbum"));
        var cover = summary.get_first_child () as Gtk.Image;
        assert (cover != null);
        wait_for_layout (window);
        assert (window.track_count == 1);
        Test.message ("External cover symlink: tracks=%u, image storage=%s, texture=%s",
            window.track_count, cover.storage_type.to_string (),
            (cover.get_paintable () is Gdk.Texture).to_string ());
        assert (cover.get_paintable () == null);
        assert (cover.storage_type == Gtk.ImageType.ICON_NAME);
        assert (cover.icon_name == "audio-x-generic-symbolic");
        assert (cover.get_mapped ());
        close_and_flush (window);
        FileUtils.unlink (folder + "/cover.jpg");
        remove_fixture (folder);
        FileUtils.unlink (external + "/artwork.jpg");
        DirUtils.remove (external);
    });
    Test.add_func ("/ui/givenAlbumWithCover_whenSelectingAlbumWithoutValidCover_thenGenericPlaceholderReturns", () => {
        string folder = fixture ();
        try {
            var artwork = new Gdk.Pixbuf (Gdk.Colorspace.RGB, false, 8, 320, 320);
            artwork.fill (0xd43b32ffU);
            artwork.save (folder + "/embedded.png", "png");
            string[] command = {"ffmpeg", "-v", "error", "-i", folder + "/song.wav",
                "-i", folder + "/embedded.png", "-map", "0:a", "-map", "1:v",
                "-c:a", "flac", "-c:v", "copy", "-disposition:v", "attached_pic",
                "-metadata", "album=Álbum con carátula", "-metadata", "artist=Artista de prueba",
                "-y", folder + "/album.flac"};
            int status;
            Process.spawn_sync (null, command, null, SpawnFlags.SEARCH_PATH, null, null, null, out status);
            assert (status == 0);
        } catch (Error e) { error ("%s", e.message); }
        // Keep the audio-only WAV as the second album, with no external artwork.
        assert (FileUtils.unlink (folder + "/embedded.png") == 0);
        var window = new Music.Window (application (), folder + "/settings.ini", Gst.ElementFactory.make ("fakesink", null));
        window.present ();
        wait_until (() => { return !window.loading && window.track_count == 2; });
        show_songs (window);
        var library = find_named (window, "library");
        select_album (library, "Artista de prueba", "Álbum con carátula");
        var summary = find_named (window, "tracks").get_first_child ();
        var cover = summary.get_first_child () as Gtk.Image;
        assert (cover != null);
        wait_for_layout (window);
        assert (has_text (summary, "Álbum con carátula"));
        assert (cover.get_paintable () is Gdk.Texture);
        select_album (library, "Artista desconocido", "Sin álbum");
        wait_for_layout (window);
        assert (has_text (summary, "Sin álbum"));
        assert (cover.get_paintable () == null);
        assert (cover.storage_type == Gtk.ImageType.ICON_NAME);
        assert (cover.icon_name == "audio-x-generic-symbolic");
        assert (cover.get_mapped ());
        close_and_flush (window);
        FileUtils.unlink (folder + "/album.flac");
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
        show_songs (window);
        var preferences = open_preferences (window);
        assert (has_text (preferences, "2 pistas cargadas · 2 archivos de audio omitidos"));
        preferences.close ();
        assert (has_text (find_named (window, "tracks"), "Todas las pistas · 2 pistas"));
        select_album (find_named (window, "library"), "Artista desconocido", "Sin álbum");
        assert (has_text (find_named (window, "tracks"), "Sin álbum — Artista desconocido · 2 pistas"));
        var stack = (Gtk.Stack) find_media_list (find_named (window, "details")).get_ancestor (typeof (Gtk.Stack));
        stack.visible_child_name = "queue";
        wait_for_layout (stack);
        var placeholder = find_named (window, "queue-empty");
        assert (placeholder.get_mapped ());
        assert (has_text (placeholder, "Agregá música desde la biblioteca"));
        close_and_flush (window);
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
        show_songs (window);
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
        close_and_flush (window);
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
        show_songs (window);
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
        close_and_flush (window);
        var reopened = new Music.Window (app, config, Gst.ElementFactory.make ("fakesink", null));
        reopened.present ();
        wait_until (() => { return !reopened.loading && reopened.track_count == 2; });
        show_songs (reopened);
        assert (has_text (find_named (reopened, "tracks"), "other"));
        close_and_flush (reopened);
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
        show_songs (window);
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
        wait_for_layout (window);
        assert (((Gtk.ListView) find_named (window, "song-list")).get_mapped ());
        assert (has_text (find_named (window, "tracks"), "song"));
        close_and_flush (window);
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
        show_songs (window);
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
        wait_for_layout (window);
        assert (((Gtk.ListView) find_named (window, "song-list")).get_mapped ());
        assert (has_text (find_named (window, "tracks"), "song"));
        assert (new Music.LocationSettings (config).load () == File.new_for_path (missing).get_uri ());
        foreach (string control in new string[] {"apply", "reload", "location", "browse"})
            assert (find_named (preferences, control).sensitive);
        assert (!find_named (preferences, "cancel").sensitive);
        notice = wait_for_notice (window, "No se pudo cargar la biblioteca. Revisá Preferencias.");
        assert (!has_text (notice, folder));
        assert (!has_text (notice, "file://"));
        assert (((Gtk.Label) find_named (preferences, "preferences-status")).label.contains ("unavailable"));
        close_and_flush (window);
        remove_fixture (folder);
    });
    Test.add_func ("/ui/preferences-save-failure", () => {
        string folder = fixture ();
        string config = folder + "/settings.ini";
        var window = new Music.Window (application (), config, Gst.ElementFactory.make ("fakesink", null));
        window.present ();
        wait_until (() => { return !window.loading && window.track_count == 1; });
        show_songs (window);
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
        close_and_flush (window);
        DirUtils.remove (config);
        remove_fixture (folder);
    });
    Test.add_func ("/ui/preferences-cancel-scan-and-close", () => {
        string folder = fixture ();
        string config = folder + "/settings.ini";
        var window = new Music.Window (application (), config, Gst.ElementFactory.make ("fakesink", null));
        window.present ();
        wait_until (() => { return !window.loading && window.track_count == 1; });
        show_songs (window);
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
        wait_for_layout (window);
        assert (((Gtk.ListView) find_named (window, "song-list")).get_mapped ());
        assert (has_text (find_named (window, "tracks"), "song"));
        assert (((Gtk.Label) find_named (preferences, "preferences-status")).label.contains ("cancelada"));
        assert (!has_text (window, "Carga cancelada"));
        assert (find_toast (window) == null);
        assert (new Music.LocationSettings (config).load () == File.new_for_path (folder).get_uri ());
        assert (reload.sensitive);
        assert (!find_named (preferences, "cancel").sensitive);
        reload.clicked ();
        assert (window.loading);
        close_and_flush (window);
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
        show_songs (window);
        var preferences = open_preferences (window);
        var detail = (Gtk.Label) find_named (preferences, "preferences-status");
        string loaded_status = detail.label;
        preferences.close ();
        // Only remove the audio after discovery, then exercise the real error via fakesink.
        assert (FileUtils.unlink (path) == 0);
        var play = find_play (window);
        var previous = (Gtk.Button) play.get_parent ().get_first_child ();
        var next = (Gtk.Button) play.get_next_sibling ();
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
        close_and_flush (window);
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
        show_songs (window);
        var play = find_play (window);
        play.clicked ();
        wait_until (() => { return play.icon_name == "media-playback-pause-symbolic"; });
        bool closing = false;
        play.notify["icon-name"].connect (() => { assert (!closing); });
        closing = true;
        close_and_flush (window);
        assert (!window.visible);
        remove_fixture (folder);
    });
    Test.add_func ("/ui/compact-footer-layout", () => {
        string folder = fixture ();
        var window = new Music.Window (application (), folder + "/settings.ini", Gst.ElementFactory.make ("fakesink", null));
        window.present ();
        wait_until (() => { return !window.loading && window.track_count == 1; });
        show_songs (window);
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
        close_and_flush (window);
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
        show_songs (window);
        var bar = find_named (window, "controls");
        var play = find_play (bar);
        var previous = (Gtk.Button) play.get_parent ().get_first_child ();
        var next = (Gtk.Button) play.get_next_sibling ();
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
        foreach (var control in new Gtk.Widget[] {next, next.get_next_sibling (), position, volume}) {
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
        foreach (var control in new Gtk.Widget[] {play, next.get_next_sibling (), position, volume}) {
            assert (bar.child_focus (Gtk.DirectionType.TAB_FORWARD));
            assert (window.get_focus () == control);
        }
        assert (previous.grab_focus ());
        assert (((Gtk.Widget) previous).activate ());
        wait_until (() => { return title.label.has_prefix ("song\n"); });
        assert (!previous.sensitive && play.sensitive && next.sensitive);
        close_and_flush (window);
        FileUtils.unlink (folder + "/track-two.wav");
        remove_fixture (folder);
    });
    Test.add_func ("/ui/footer-volume-group", () => {
        string folder = fixture ();
        var window = new Music.Window (application (), folder + "/settings.ini", Gst.ElementFactory.make ("fakesink", null));
        window.present ();
        wait_until (() => { return !window.loading; });
        show_songs (window);
        var bar = find_named (window, "controls");
        wait_for_layout (bar);
        var volume = find_named (bar, "volume");
        var icon = bounds_in (volume.get_prev_sibling (), bar);
        var slider = bounds_in (volume, bar);
        float gap = slider.get_x () - icon.get_x () - icon.get_width ();
        Test.message ("Volume icon/slider gap: %.0f", gap);
        assert (gap >= 0 && gap <= 6);
        close_and_flush (window);
        remove_fixture (folder);
    });
    Test.add_func ("/ui/givenLibraryPanel_whenWindowWidens_thenWidthRemainsProportional", () => {
        string folder = fixture ();
        var window = new Music.Window (application (), folder + "/settings.ini", Gst.ElementFactory.make ("fakesink", null));
        window.set_default_size (1280, 800);
        window.present ();
        wait_until (() => { return !window.loading && window.track_count == 1; });
        show_songs (window);
        wait_for_layout (window);
        var panels = (Gtk.Paned) find_named (window, "library").get_ancestor (typeof (Gtk.Paned));
        int initial_total = panels.get_width ();
        int initial_library = panels.start_child.get_width ();
        assert (initial_total > 0 && initial_library > 0);
        double proportion = (double) initial_library / initial_total;

        window.set_default_size (1600, 800);
        wait_for_layout (window);
        assert (window.get_surface ().get_width () == 1600);
        assert (panels.get_width () > initial_total);
        double expected_width = proportion * panels.get_width ();
        int actual_width = panels.start_child.get_width ();
        Test.message ("Library proportion: %d/%d -> %d/%d; expected width=%.2f",
            initial_library, initial_total, actual_width, panels.get_width (), expected_width);
        // Allow pixel rounding, not a content-driven or fixed-pixel panel width.
        assert ((actual_width - expected_width).abs () <= 2);
        close_and_flush (window);
        remove_fixture (folder);
    });
    Test.add_func ("/ui/givenLongLibraryGroup_whenManuallyAdjustedThenWindowWidens_thenChosenProportionRemains", () => {
        string folder = fixture ();
        var window = new Music.Window (application (), folder + "/settings.ini", Gst.ElementFactory.make ("fakesink", null));
        window.set_default_size (1280, 800);
        window.present ();
        wait_until (() => { return !window.loading && window.track_count == 1; });
        show_songs (window);
        wait_for_layout (window);
        var library = find_named (window, "library");
        var panels = (Gtk.Paned) library.get_ancestor (typeof (Gtk.Paned));
        int initial_total = panels.get_width ();
        int initial_library = panels.start_child.get_width ();

        string long_album = "Álbum de nombre muy largo " + string.nfill (180, 'A');
        try {
            string[] command = {"ffmpeg", "-v", "error", "-i", folder + "/song.wav",
                "-c", "copy", "-metadata", "album=" + long_album, "-y", folder + "/long-group.wav"};
            int status;
            Process.spawn_sync (null, command, null, SpawnFlags.SEARCH_PATH, null, null, null, out status);
            assert (status == 0);
        } catch (Error e) { error ("%s", e.message); }
        window.load_library.begin (folder);
        wait_until (() => { return !window.loading && window.track_count == 2; });
        select_album (library, "Artista desconocido", long_album);
        wait_for_layout (window);
        assert (has_text (window, long_album));
        Test.message ("Long group: library=%d -> %d, total=%d -> %d",
            initial_library, panels.start_child.get_width (), initial_total, panels.get_width ());
        assert (panels.get_width () == initial_total);
        assert ((panels.start_child.get_width () - initial_library).abs () <= 2);

        panels.position = 384;
        wait_for_layout (window);
        int chosen_width = panels.start_child.get_width ();
        assert ((chosen_width - 384).abs () <= 2);
        double chosen_proportion = (double) chosen_width / panels.get_width ();
        window.set_default_size (1600, 800);
        wait_for_layout (window);
        assert (window.get_surface ().get_width () == 1600);
        assert (panels.get_width () > initial_total);
        double expected_width = chosen_proportion * panels.get_width ();
        Test.message ("Chosen proportion: %d/%d -> %d/%d; expected width=%.2f",
            chosen_width, initial_total, panels.start_child.get_width (), panels.get_width (), expected_width);
        assert ((panels.start_child.get_width () - expected_width).abs () <= 2);
        close_and_flush (window);
        FileUtils.unlink (folder + "/long-group.wav");
        remove_fixture (folder);
    });
    Test.add_func ("/ui/library-panel-free-width", () => {
        string folder = fixture ();
        var window = new Music.Window (application (), folder + "/settings.ini", Gst.ElementFactory.make ("fakesink", null));
        window.present ();
        wait_until (() => { return !window.loading && window.track_count == 1; });
        show_songs (window);
        var panels = (Gtk.Paned) find_named (window, "library").get_ancestor (typeof (Gtk.Paned));
        foreach (int width in new int[] {1280, 1600}) {
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
        close_and_flush (window);
        remove_fixture (folder);
    });
    Test.add_func ("/ui/tracks-details-free-width", () => {
        string folder = fixture ();
        var window = new Music.Window (application (), folder + "/settings.ini", Gst.ElementFactory.make ("fakesink", null));
        window.present ();
        wait_until (() => { return !window.loading && window.track_count == 1; });
        show_songs (window);
        var inner = (Gtk.Paned) find_named (window, "tracks").get_ancestor (typeof (Gtk.Paned));
        foreach (int width in new int[] {1280, 1600}) {
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
        close_and_flush (window);
        remove_fixture (folder);
    });
    Test.add_func ("/ui/panels-extremes-and-restore", () => {
        string folder = fixture ("8");
        var sink = Gst.ElementFactory.make ("fakesink", null);
        sink.set ("sync", true);
        var window = new Music.Window (application (), folder + "/settings.ini", sink);
        window.present ();
        wait_until (() => { return !window.loading && window.track_count == 1; });
        show_songs (window);
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
        foreach (int width in new int[] {1280, 1600}) {
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
                assert (has_text (library, "Canciones"));
                assert (has_text (tracks, "song"));
                assert (has_text (details, "Artista:"));
                assert (has_text (details, "song"));
                capture_if_requested (window, "-restored-%d".printf (width));
            }
        }
        close_and_flush (window);
        remove_fixture (folder);
    });
    Test.add_func ("/ui/visual-album-queue-actions-search-artwork", test_visual_album_queue_actions);
    Test.add_func ("/ui/queue-import-drop-and-cancel", test_queue_import_drop_and_cancel);
    Test.add_func ("/ui/queue-session-reopen-no-autoplay", test_queue_session_reopen);
    Test.add_func ("/ui/adaptive-overlays-restore-proportions", test_adaptive_overlays_restore_proportions);
    Test.add_func ("/ui/initial-empty-states-survive-navigation", test_initial_empty_states_survive_navigation);
    Test.add_func ("/ui/native-pointer-drag-copy-move-files-escape", test_native_pointer_drag);
    return Test.run ();
}
