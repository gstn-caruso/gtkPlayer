using Music;

string fixture;

void make_audio (string path) {
    string[] args = {"ffmpeg", "-v", "error", "-f", "lavfi", "-i", "sine=frequency=440:duration=0.4", "-metadata", "title=Prueba", "-metadata", "artist=Artista", "-metadata", "album=Disco", "-metadata", "track=2", "-y", path};
    try {
        int status;
        Process.spawn_sync (null, args, null, SpawnFlags.SEARCH_PATH, null, null, null, out status);
        assert (status == 0);
    } catch (Error e) { error ("Fixture: %s", e.message); }
}

void test_scan () {
    var loop = new MainLoop ();
    var scanner = new Music.Scanner ();
    scanner.scan.begin (File.new_for_path (fixture), new Cancellable (), (obj, result) => {
        try {
            var tracks = scanner.scan.end (result);
            assert_cmpint (tracks.length, CompareOperator.EQ, 1);
            assert (tracks[0].uri.has_suffix ("/nested/song.flac"));
            assert_cmpstr (tracks[0].title, CompareOperator.EQ, "Prueba");
            assert_cmpstr (tracks[0].artist, CompareOperator.EQ, "Artista");
            assert_cmpstr (tracks[0].album, CompareOperator.EQ, "Disco");
            assert_cmpuint (tracks[0].number, CompareOperator.EQ, 2);
            assert (tracks[0].duration > 0);
        } catch (Error e) { error ("Escaneo: %s", e.message); }
        loop.quit ();
    });
    loop.run ();
}

void test_scan_unavailable () {
    var loop = new MainLoop ();
    var scanner = new Music.Scanner ();
    scanner.scan.begin (File.new_for_path (fixture + "/absent"), new Cancellable (), (obj, result) => {
        bool failed = false;
        try { scanner.scan.end (result); } catch (IOError.NOT_FOUND e) { failed = true; }
        catch (Error e) { error ("Error inesperado: %s", e.message); }
        assert (failed);
        loop.quit ();
    });
    loop.run ();
}

void test_cancelled () {
    var loop = new MainLoop ();
    var scanner = new Music.Scanner ();
    var cancel = new Cancellable ();
    cancel.cancel ();
    scanner.scan.begin (File.new_for_path (fixture), cancel, (obj, result) => {
        bool failed = false;
        try { scanner.scan.end (result); } catch (IOError.CANCELLED e) { failed = true; }
        catch (Error e) { error ("Error inesperado: %s", e.message); }
        assert (failed);
        loop.quit ();
    });
    loop.run ();
}

void test_queue () {
    var queue = new PlayQueue ();
    assert (queue.current == null);
    assert (!queue.next ());
    assert (!queue.previous ());
    var a = new Track ("file:///a.flac", "A");
    var b = new Track ("file:///b.flac", "B");
    queue.replace ({a, b});
    assert (!queue.select (-1));
    assert (!queue.select (2));
    assert (queue.select (0));
    assert (queue.current == a);
    assert (!queue.previous ());
    assert (queue.next ());
    assert (queue.current == b);
    assert (!queue.next ());
    assert (queue.current == b);
    assert (queue.previous ());
    assert (queue.current == a);
    queue.replace ({});
    assert (queue.current == null);
    assert (queue.index == -1);
}

void test_playback_eos () {
    var queue = new PlayQueue ();
    string uri = File.new_for_path (fixture + "/nested/song.flac").get_uri ();
    queue.replace ({new Track (uri, "A"), new Track (uri, "B")});
    queue.select (0);
    var sink = Gst.ElementFactory.make ("fakesink", null);
    assert (sink != null);
    sink.set ("sync", true);
    var player = new Player (queue, sink);
    var loop = new MainLoop ();
    bool finished = false;
    bool saw_next = false;
    player.changed.connect (() => { if (queue.index == 1) saw_next = true; });
    player.failure.connect ((message) => { error ("Reproducción: %s", message); });
    player.finished.connect (() => { finished = true; loop.quit (); });
    uint timeout = Timeout.add_seconds (5, () => { loop.quit (); return Source.REMOVE; });
    player.play ();
    loop.run ();
    if (finished) Source.remove (timeout);
    assert (finished);
    assert (saw_next);
    assert (queue.index == 1);
    assert (player.state == Gst.State.NULL);
    player.shutdown ();
}

void test_player_controls () {
    var queue = new PlayQueue ();
    queue.replace ({new Track (File.new_for_path (fixture + "/nested/song.flac").get_uri (), "Control")});
    queue.select (0);
    var sink = Gst.ElementFactory.make ("fakesink", null);
    sink.set ("sync", true);
    var player = new Player (queue, sink);
    var loop = new MainLoop ();
    bool paused = false;
    player.changed.connect (() => {
        if (player.state == Gst.State.PLAYING) player.pause ();
        if (player.state == Gst.State.PAUSED) { paused = true; loop.quit (); }
    });
    uint timeout = Timeout.add_seconds (3, () => { loop.quit (); return Source.REMOVE; });
    player.play ();
    loop.run ();
    if (paused) Source.remove (timeout);
    assert (paused);
    assert (player.duration () > 0);
    assert (player.seek (0.1));
    player.volume = 0.25;
    assert (player.volume == 0.25);
    player.shutdown ();
}

void test_player_error () {
    var queue = new PlayQueue ();
    queue.replace ({new Track (File.new_for_path (fixture + "/missing.flac").get_uri (), "Ausente"),
                    new Track (File.new_for_path (fixture + "/nested/song.flac").get_uri (), "No avanzar")});
    queue.select (0);
    var player = new Player (queue, Gst.ElementFactory.make ("fakesink", null));
    var loop = new MainLoop ();
    bool failed = false;
    player.failure.connect ((message) => { assert (message.length > 0); failed = true; loop.quit (); });
    uint timeout = Timeout.add_seconds (3, () => { loop.quit (); return Source.REMOVE; });
    player.play ();
    if (!failed) loop.run ();
    if (failed) Source.remove (timeout);
    assert (failed);
    assert (queue.index == 0);
    assert (player.state == Gst.State.NULL);
    player.shutdown ();
}

int main (string[] args) {
    Test.init (ref args);
    Gst.init (ref args);
    try {
        fixture = DirUtils.make_tmp ("gtkplayer-tests-XXXXXX");
        DirUtils.create (fixture + "/nested", 0700);
        make_audio (fixture + "/nested/song.flac");
        FileUtils.set_contents (fixture + "/notes.txt", "No es audio");
        File.new_for_path (fixture + "/alias.flac").make_symbolic_link (fixture + "/nested/song.flac");
        File.new_for_path (fixture + "/loop").make_symbolic_link (fixture);
    } catch (Error e) { error ("Preparación: %s", e.message); }
    Test.add_func ("/library/recursive-tags-no-symlinks", test_scan);
    Test.add_func ("/library/regular-without-symlink-attribute", () => {
        var info = new FileInfo ();
        info.set_name ("song.flac");
        info.set_file_type (FileType.REGULAR);
        assert (!info.has_attribute (FileAttribute.STANDARD_IS_SYMLINK));
        assert (!Music.Scanner.is_symbolic_link (info));
    });
    Test.add_func ("/library/directory-without-symlink-attribute", () => {
        var info = new FileInfo ();
        info.set_name ("nested");
        info.set_file_type (FileType.DIRECTORY);
        assert (!info.has_attribute (FileAttribute.STANDARD_IS_SYMLINK));
        assert (!Music.Scanner.is_symbolic_link (info));
    });
    Test.add_func ("/library/symlink-type-without-symlink-attribute", () => {
        var info = new FileInfo ();
        info.set_name ("alias.flac");
        info.set_file_type (FileType.SYMBOLIC_LINK);
        assert (!info.has_attribute (FileAttribute.STANDARD_IS_SYMLINK));
        assert (Music.Scanner.is_symbolic_link (info));
    });
    Test.add_func ("/library/symlink-attribute-with-regular-type", () => {
        var info = new FileInfo ();
        info.set_name ("alias.flac");
        info.set_file_type (FileType.REGULAR);
        info.set_is_symlink (true);
        assert (Music.Scanner.is_symbolic_link (info));
    });
    Test.add_func ("/library/unavailable", test_scan_unavailable);
    Test.add_func ("/library/cancelled", test_cancelled);
    Test.add_func ("/queue/navigation-boundaries", test_queue);
    Test.add_func ("/player/eos-next-and-finish", test_playback_eos);
    Test.add_func ("/player/pause-seek-volume", test_player_controls);
    Test.add_func ("/player/error-does-not-skip", test_player_error);
    int status = Test.run ();
    FileUtils.unlink (fixture + "/alias.flac");
    FileUtils.unlink (fixture + "/loop");
    FileUtils.unlink (fixture + "/notes.txt");
    FileUtils.unlink (fixture + "/nested/song.flac");
    DirUtils.remove (fixture + "/nested");
    DirUtils.remove (fixture);
    return status;
}
