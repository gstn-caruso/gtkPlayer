int main (string[] args) {
    Gst.init (ref args);
    var app = new Adw.Application ("io.github.gtkplayer.Player", ApplicationFlags.DEFAULT_FLAGS);
    app.activate.connect (() => {
        if (app.active_window != null) { app.active_window.present (); return; }
        var window = new Music.Window (app, Path.build_filename (Environment.get_user_config_dir (), "gtkplayer", "settings.ini"));
        window.present ();
    });
    return app.run (args);
}
