Gtk.Widget? find_named (Gtk.Widget widget, string name) {
    if (widget.name == name) return widget;
    for (var child = widget.get_first_child (); child != null; child = child.get_next_sibling ()) {
        var found = find_named (child, name);
        if (found != null) return found;
    }
    return null;
}

int main (string[] args) {
    Test.init (ref args);
    Gst.init (ref args);
    Adw.init ();
    Test.add_func ("/ui/activation-empty-four-zones", () => {
        string config = "";
        try { config = DirUtils.make_tmp ("gtkplayer-ui-XXXXXX"); }
        catch (Error e) { error ("%s", e.message); }
        var app = new Adw.Application ("io.github.gtkplayer.Test", ApplicationFlags.NON_UNIQUE);
        try { app.register (); } catch (Error e) { error ("%s", e.message); }
        Music.Window? window = null;
        app.activate.connect (() => {
            window = new Music.Window (app, config + "/settings.ini", Gst.ElementFactory.make ("fakesink", null));
            window.present ();
        });
        app.activate ();
        var loop = new MainLoop ();
        Timeout.add (200, () => {
            assert (window.visible);
            foreach (string zone in new string[] {"library", "tracks", "details", "controls"})
                assert (find_named (window, zone) != null);
            var location = find_named (window, "location") as Gtk.Entry;
            assert (location != null);
            assert (location.text == "smb://nas.local/public/multimedia/Música");
            assert (find_named (window, "load").sensitive);
            assert (!find_named (window, "cancel").sensitive);
            assert (!FileUtils.test (config + "/settings.ini", FileTest.EXISTS));
            window.close ();
            loop.quit ();
            return Source.REMOVE;
        });
        loop.run ();
        DirUtils.remove (config);
    });
    Test.add_func ("/ui/explicit-local-load-and-remember", () => {
        string folder = "";
        try {
            folder = DirUtils.make_tmp ("gtkplayer-load-XXXXXX");
            string[] command = {"ffmpeg", "-v", "error", "-f", "lavfi", "-i", "sine=duration=0.2", "-y", folder + "/song.wav"};
            int status;
            Process.spawn_sync (null, command, null, SpawnFlags.SEARCH_PATH, null, null, null, out status);
            assert (status == 0);
        } catch (Error e) { error ("%s", e.message); }
        var app = new Adw.Application ("io.github.gtkplayer.LoadTest", ApplicationFlags.NON_UNIQUE);
        try { app.register (); } catch (Error e) { error ("%s", e.message); }
        string config = folder + "/settings.ini";
        var window = new Music.Window (app, config, Gst.ElementFactory.make ("fakesink", null));
        window.present ();
        var loop = new MainLoop ();
        window.load_library.begin (folder, (obj, result) => {
            window.load_library.end (result);
            assert (window.track_count == 1);
            assert (!window.loading);
            assert (!find_named (window, "cancel").sensitive);
            assert (FileUtils.test (config, FileTest.EXISTS));
            window.close ();
            var reopened = new Music.Window (app, config, Gst.ElementFactory.make ("fakesink", null));
            var entry = find_named (reopened, "location") as Gtk.Entry;
            assert (entry.text == File.new_for_path (folder).get_uri ());
            assert (reopened.track_count == 0);
            reopened.close ();
            loop.quit ();
        });
        loop.run ();
        FileUtils.unlink (folder + "/song.wav");
        FileUtils.unlink (config);
        DirUtils.remove (folder);
    });
    return Test.run ();
}
