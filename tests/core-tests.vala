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
    scanner.scan.begin (File.new_for_path (fixture), new Cancellable (), {}, (obj, result) => {
        try {
            var tracks = scanner.scan.end (result);
            assert_cmpint (tracks.length, CompareOperator.EQ, 1);
            assert (tracks[0].uri.has_suffix ("/nested/song.flac"));
            assert_cmpstr (tracks[0].title, CompareOperator.EQ, "Prueba");
            assert_cmpstr (tracks[0].artist, CompareOperator.EQ, "Artista");
            assert_cmpstr (tracks[0].album, CompareOperator.EQ, "Disco");
            assert_cmpuint (tracks[0].number, CompareOperator.EQ, 2);
            assert (tracks[0].duration > 0);
            assert (tracks[0].codec == "FLAC" && tracks[0].sample_rate == 44100);
            assert (tracks[0].bit_depth == 16 && tracks[0].channels == 1);
            assert (tracks[0].audio_description () == "FLAC · 44.1 kHz · 16 bits · Mono");
            var cache = new Music.LibraryCache (fixture + "/audio-info-cache");
            cache.save ("file:///audio-info", tracks);
            var loaded = cache.load ("file:///audio-info");
            assert (loaded[0].audio_description () == tracks[0].audio_description ());
            var queue = new PlayQueue ();
            queue.append (tracks);
            queue.select (0);
            var session = QueueSession.decode (new QueueSession.capture (queue, 0).encode ());
            assert (session.entries[0].track.audio_description () == tracks[0].audio_description ());
            // Simulate an old cache: a matching fingerprint must still be enriched once.
            loaded[0].audio_info_known = false;
            assert (!Music.LibraryCache.same_contents (loaded, tracks, new Cancellable ()));
            cache.save ("file:///audio-info", loaded);
            loaded = cache.load ("file:///audio-info");
            assert (loaded[0].codec == "" && !loaded[0].audio_info_known);
            var upgrade_loop = new MainLoop ();
            var upgrade = new Music.Scanner ();
            upgrade.scan.begin (File.new_for_path (fixture), new Cancellable (), loaded, (source, result2) => {
                try {
                    var enriched = upgrade.scan.end (result2);
                    assert (upgrade.discovered == 1);
                    assert (enriched[0].audio_description () == "FLAC · 44.1 kHz · 16 bits · Mono");
                } catch (Error e) { error ("Migración: %s", e.message); }
                upgrade_loop.quit ();
            });
            upgrade_loop.run ();
        } catch (Error e) { error ("Escaneo: %s", e.message); }
        loop.quit ();
    });
    loop.run ();
}

void test_scan_unavailable () {
    var loop = new MainLoop ();
    var scanner = new Music.Scanner ();
    scanner.scan.begin (File.new_for_path (fixture + "/absent"), new Cancellable (), {}, (obj, result) => {
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
    scanner.scan.begin (File.new_for_path (fixture), cancel, {}, (obj, result) => {
        bool failed = false;
        try { scanner.scan.end (result); } catch (IOError.CANCELLED e) { failed = true; }
        catch (Error e) { error ("Error inesperado: %s", e.message); }
        assert (failed);
        loop.quit ();
    });
    loop.run ();
}

void givenTwoCachedTracks_whenCacheIsReopened_thenTracksAndMetadataArePreserved () {
    string path = fixture + "/library-cache";
    string source_uri = "smb://server/music";
    var first = new Track ("smb://server/music/a.flac", "Primera");
    first.artist = "Artista A";
    first.album = "Álbum A";
    first.number = 2;
    first.duration = 123456789;
    first.cover_data = new Bytes (new uint8[] {0, 127, 255});
    var second = new Track ("smb://server/music/b.ogg", "Segunda");
    second.artist = "Artista B";
    second.album = "Álbum B";
    second.number = 9;
    second.duration = 987654321;
    try {
        var writer = new Music.LibraryCache (path);
        writer.save (source_uri, {first, second});
        var reader = new Music.LibraryCache (path);
        Track[] loaded = reader.load (source_uri);
        assert_cmpint (loaded.length, CompareOperator.EQ, 2);
        assert_cmpstr (loaded[0].uri, CompareOperator.EQ, first.uri);
        assert_cmpstr (loaded[0].title, CompareOperator.EQ, first.title);
        assert_cmpstr (loaded[0].artist, CompareOperator.EQ, first.artist);
        assert_cmpstr (loaded[0].album, CompareOperator.EQ, first.album);
        assert (loaded[0].number == first.number);
        assert (loaded[0].duration == first.duration);
        assert (loaded[0].cover_data != null && loaded[0].cover_data.compare (first.cover_data) == 0);
        assert_cmpstr (loaded[1].uri, CompareOperator.EQ, second.uri);
        assert_cmpstr (loaded[1].title, CompareOperator.EQ, second.title);
        assert_cmpstr (loaded[1].artist, CompareOperator.EQ, second.artist);
        assert_cmpstr (loaded[1].album, CompareOperator.EQ, second.album);
        assert (loaded[1].number == second.number);
        assert (loaded[1].duration == second.duration);
        assert (loaded[1].cover_data == null);
    } catch (Error e) { error ("Caché: %s", e.message); }
}

void givenTracksSharingArtwork_whenCacheIsReopened_thenArtworkIsStoredAndLoadedOnce () {
    string path = fixture + "/shared-artwork-cache";
    string source_uri = "smb://server/shared-artwork";
    uint8[] artwork = new uint8[64 * 1024];
    for (int i = 0; i < artwork.length; i++) artwork[i] = (uint8) (i % 251);
    var cover = new Bytes (artwork);
    Track[] tracks = {};
    for (int i = 0; i < 8; i++) {
        var track = new Track (source_uri + "/%d.flac".printf (i), "Pista %d".printf (i));
        track.artist = "Artista %d".printf (i);
        track.album = "Álbum compartido";
        track.number = (uint) i + 1;
        track.duration = 123456789 + i;
        track.cover_data = cover;
        tracks += track;
    }
    try {
        new Music.LibraryCache (path).save (source_uri, tracks);
        Track[] loaded = new Music.LibraryCache (path).load (source_uri);
        assert_cmpint (loaded.length, CompareOperator.EQ, tracks.length);
        bool shared_artwork = true;
        for (int i = 0; i < loaded.length; i++) {
            assert_cmpstr (loaded[i].uri, CompareOperator.EQ, tracks[i].uri);
            assert_cmpstr (loaded[i].title, CompareOperator.EQ, tracks[i].title);
            assert_cmpstr (loaded[i].artist, CompareOperator.EQ, tracks[i].artist);
            assert_cmpstr (loaded[i].album, CompareOperator.EQ, tracks[i].album);
            assert_cmpuint (loaded[i].number, CompareOperator.EQ, tracks[i].number);
            assert (loaded[i].duration == tracks[i].duration);
            assert (loaded[i].cover_data != null && loaded[i].cover_data.compare (cover) == 0);
            shared_artwork = shared_artwork && loaded[i].cover_data == loaded[0].cover_data;
        }
        int64 stored_size = 0;
        var entries = File.new_for_path (path).enumerate_children (
            FileAttribute.STANDARD_SIZE, FileQueryInfoFlags.NONE);
        FileInfo? entry;
        while ((entry = entries.next_file ()) != null) stored_size += entry.get_size ();
        entries.close ();
        int64 storage_limit = 3 * (((artwork.length + 2) / 3) * 4);
        Test.message ("Caché: %s bytes; límite: %s; Bytes compartidos: %s",
            stored_size.to_string (), storage_limit.to_string (), shared_artwork.to_string ());
        assert (stored_size < storage_limit);
        assert (shared_artwork);
    } catch (Error e) { error ("Caché con portada compartida: %s", e.message); }
}

void givenPersistedLibrary_whenFilesChange_thenOnlyNewAndModifiedAudioAreDiscovered () {
    try {
        string root = DirUtils.make_tmp ("gtkplayer-incremental-XXXXXX");
        var folder = File.new_for_path (root + "/music");
        folder.make_directory ();
        string unchanged = root + "/music/unchanged.flac";
        string modified = root + "/music/modified.flac";
        string removed = root + "/music/removed.flac";
        string added = root + "/music/added.flac";
        make_audio (unchanged);
        make_audio (modified);
        make_audio (removed);

        var first_scanner = new Music.Scanner ();
        var loop = new MainLoop ();
        Track[] original = {};
        first_scanner.scan.begin (folder, new Cancellable (), {}, (obj, result) => {
            try { original = first_scanner.scan.end (result); }
            catch (Error e) { error ("Primer escaneo: %s", e.message); }
            loop.quit ();
        });
        loop.run ();
        assert_cmpint (original.length, CompareOperator.EQ, 3);
        string source_uri = folder.get_uri ();
        string cache_path = root + "/cache";
        new Music.LibraryCache (cache_path).save (source_uri, original);
        Track[] previous = new Music.LibraryCache (cache_path).load (source_uri);
        assert_cmpint (previous.length, CompareOperator.EQ, 3);

        var before = File.new_for_path (modified).query_info (FileAttribute.STANDARD_SIZE, FileQueryInfoFlags.NONE);
        string[] args = {"ffmpeg", "-v", "error", "-f", "lavfi", "-i", "sine=frequency=440:duration=1.2", "-metadata", "title=Actualizada", "-y", modified};
        int status;
        Process.spawn_sync (null, args, null, SpawnFlags.SEARCH_PATH, null, null, null, out status);
        assert (status == 0);
        var after = File.new_for_path (modified).query_info (FileAttribute.STANDARD_SIZE, FileQueryInfoFlags.NONE);
        assert (before.get_size () != after.get_size ());
        make_audio (added);
        File.new_for_path (removed).delete ();

        var scanner = new Music.Scanner ();
        Track[] reconciled = {};
        scanner.scan.begin (folder, new Cancellable (), previous, (obj, result) => {
            try { reconciled = scanner.scan.end (result); }
            catch (Error e) { error ("Reconciliación: %s", e.message); }
            loop.quit ();
        });
        loop.run ();
        assert_cmpint (reconciled.length, CompareOperator.EQ, 3);
        bool found_unchanged = false;
        bool found_modified = false;
        bool found_added = false;
        foreach (var track in reconciled) {
            if (track.uri == File.new_for_path (unchanged).get_uri ()) {
                found_unchanged = true;
                assert_cmpstr (track.title, CompareOperator.EQ, "Prueba");
            } else if (track.uri == File.new_for_path (modified).get_uri ()) {
                found_modified = true;
                assert_cmpstr (track.title, CompareOperator.EQ, "Actualizada");
            } else if (track.uri == File.new_for_path (added).get_uri ()) {
                found_added = true;
                assert_cmpstr (track.title, CompareOperator.EQ, "Prueba");
            } else {
                assert_not_reached ();
            }
        }
        assert (found_unchanged && found_modified && found_added);
        assert_cmpuint (scanner.discovered, CompareOperator.EQ, 2);

        File.new_for_path (unchanged).delete ();
        File.new_for_path (modified).delete ();
        File.new_for_path (added).delete ();
        folder.delete ();
        string cache_name = Checksum.compute_for_string (ChecksumType.SHA256, source_uri) + ".ini";
        File.new_for_path (Path.build_filename (cache_path, cache_name)).delete ();
        File.new_for_path (cache_path).delete ();
        File.new_for_path (root).delete ();
    } catch (Error e) { error ("Fixture incremental: %s", e.message); }
}

void givenCachedTrack_whenChangedAudioCannotBeRead_thenKnownMetadataIsRetained () {
    try {
        string root = DirUtils.make_tmp ("gtkplayer-transient-XXXXXX");
        var folder = File.new_for_path (root + "/music");
        folder.make_directory ();
        string audio = root + "/music/song.wav";
        make_audio (audio);
        FileUtils.set_contents (root + "/music/cover.jpg", "carátula anterior");
        var loop = new MainLoop ();
        var first_scanner = new Music.Scanner ();
        Track[] original = {};
        first_scanner.scan.begin (folder, new Cancellable (), {}, (obj, result) => {
            try { original = first_scanner.scan.end (result); }
            catch (Error e) { error ("Primer escaneo: %s", e.message); }
            loop.quit ();
        });
        loop.run ();
        assert_cmpint (original.length, CompareOperator.EQ, 1);
        assert (original[0].cover_data != null);
        string source_uri = folder.get_uri ();
        string cache_path = root + "/cache";
        new Music.LibraryCache (cache_path).save (source_uri, original);
        Track[] previous = new Music.LibraryCache (cache_path).load (source_uri);
        assert_cmpint (previous.length, CompareOperator.EQ, 1);

        string updated = root + "/updated.wav";
        string[] args = {"ffmpeg", "-v", "error", "-f", "lavfi", "-i", "sine=frequency=440:duration=1.2", "-metadata", "title=Actualizada", "-y", updated};
        int status;
        Process.spawn_sync (null, args, null, SpawnFlags.SEARCH_PATH, null, null, null, out status);
        assert (status == 0);
        uint8[] valid;
        FileUtils.get_data (updated, out valid);
        uint8[] invalid = new uint8[valid.length];
        FileUtils.set_data (audio, invalid);
        File.new_for_path (audio).copy (File.new_for_path (root + "/timestamp"), FileCopyFlags.ALL_METADATA);

        var scanner = new Music.Scanner ();
        Track[] retained = {};
        scanner.scan.begin (folder, new Cancellable (), previous, (obj, result) => {
            try { retained = scanner.scan.end (result); }
            catch (Error e) { error ("Reconciliación: %s", e.message); }
            loop.quit ();
        });
        loop.run ();
        assert_cmpint (retained.length, CompareOperator.EQ, 1);
        assert_cmpuint (scanner.skipped, CompareOperator.EQ, 1);
        assert_cmpstr (retained[0].uri, CompareOperator.EQ, previous[0].uri);
        assert_cmpstr (retained[0].title, CompareOperator.EQ, previous[0].title);
        assert_cmpstr (retained[0].artist, CompareOperator.EQ, previous[0].artist);
        assert_cmpstr (retained[0].album, CompareOperator.EQ, previous[0].album);
        assert_cmpuint (retained[0].number, CompareOperator.EQ, previous[0].number);
        assert (retained[0].duration == previous[0].duration);
        assert (retained[0].cover_data != null && retained[0].cover_data.compare (previous[0].cover_data) == 0);

        new Music.LibraryCache (cache_path).save (source_uri, retained);
        Track[] fallback = new Music.LibraryCache (cache_path).load (source_uri);
        FileUtils.set_data (audio, valid);
        string[] touch_args = {"touch", "-r", root + "/timestamp", audio};
        Process.spawn_sync (null, touch_args, null, SpawnFlags.SEARCH_PATH, null, null, null, out status);
        assert (status == 0);
        Track[] retried = {};
        scanner.scan.begin (folder, new Cancellable (), fallback, (obj, result) => {
            try { retried = scanner.scan.end (result); }
            catch (Error e) { error ("Reintento: %s", e.message); }
            loop.quit ();
        });
        loop.run ();
        assert_cmpint (retried.length, CompareOperator.EQ, 1);
        assert_cmpstr (retried[0].title, CompareOperator.EQ, "Actualizada");
        assert_cmpuint (scanner.discovered, CompareOperator.EQ, 1);
        assert_cmpuint (scanner.skipped, CompareOperator.EQ, 0);
    } catch (Error e) { error ("Fixture transitorio: %s", e.message); }
}

void givenCachedAudio_whenFolderCoverChanges_thenArtworkRefreshesWithoutRediscoveringAudio () {
    try {
        string root = DirUtils.make_tmp ("gtkplayer-cover-change-XXXXXX");
        var folder = File.new_for_path (root + "/music");
        folder.make_directory ();
        make_audio (root + "/music/song.wav");
        string cover = root + "/music/cover.jpg";
        string[] first_image = {"ffmpeg", "-v", "error", "-f", "lavfi", "-i", "color=red:s=16x16", "-frames:v", "1", "-threads", "1", "-y", cover};
        int status;
        Process.spawn_sync (null, first_image, null, SpawnFlags.SEARCH_PATH, null, null, null, out status);
        assert (status == 0);
        Bytes first_cover = File.new_for_path (cover).load_bytes (null, null);

        var loop = new MainLoop ();
        var scanner = new Music.Scanner ();
        Track[] original = {};
        scanner.scan.begin (folder, new Cancellable (), {}, (obj, result) => {
            try { original = scanner.scan.end (result); }
            catch (Error e) { error ("Primer escaneo: %s", e.message); }
            loop.quit ();
        });
        loop.run ();
        assert_cmpint (original.length, CompareOperator.EQ, 1);
        assert (original[0].cover_data != null && original[0].cover_data.compare (first_cover) == 0);
        string source_uri = folder.get_uri ();
        string cache_path = root + "/cache";
        new Music.LibraryCache (cache_path).save (source_uri, original);
        Track[] previous = new Music.LibraryCache (cache_path).load (source_uri);
        assert_cmpint (previous.length, CompareOperator.EQ, 1);
        assert (previous[0].cover_data != null && previous[0].cover_data.compare (first_cover) == 0);

        string[] second_image = {"ffmpeg", "-v", "error", "-f", "lavfi", "-i", "color=blue:s=32x32", "-frames:v", "1", "-threads", "1", "-y", cover};
        Process.spawn_sync (null, second_image, null, SpawnFlags.SEARCH_PATH, null, null, null, out status);
        assert (status == 0);
        Bytes updated_cover = File.new_for_path (cover).load_bytes (null, null);
        assert (first_cover.get_size () != updated_cover.get_size ());

        Track[] reconciled = {};
        scanner.scan.begin (folder, new Cancellable (), previous, (obj, result) => {
            try { reconciled = scanner.scan.end (result); }
            catch (Error e) { error ("Reconciliación: %s", e.message); }
            loop.quit ();
        });
        loop.run ();
        assert_cmpint (reconciled.length, CompareOperator.EQ, 1);
        assert_cmpuint (scanner.discovered, CompareOperator.EQ, 0);
        assert (reconciled[0].cover_data != null && reconciled[0].cover_data.compare (updated_cover) == 0);
    } catch (Error e) { error ("Fixture de portada: %s", e.message); }
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

void test_queue_edits () {
    var queue = new PlayQueue ();
    var a = new Track ("file:///a.flac", "A");
    var b = new Track ("file:///b.flac", "B");
    queue.append ({a, a, b});
    assert (queue.current == null);
    assert (queue.entries[0].id != queue.entries[1].id);
    queue.select (1);
    string current = queue.current_entry.id;
    queue.insert ({b}, 0);
    assert (queue.index == 2 && queue.current_entry.id == current);
    queue.move (2, 0);
    assert (queue.index == 0 && queue.current_entry.id == current);
    queue.move (3, 1);
    assert (queue.index == 0 && queue.current_entry.id == current);
    string[] before = {};
    foreach (var entry in queue.entries) before += entry.id;
    assert (queue.clear ());
    assert (queue.entries.length == 1 && queue.current_entry.id == current);
    assert (queue.undo_clear ());
    for (int i = 0; i < before.length; i++) assert (queue.entries[i].id == before[i]);
    queue.clear ();
    queue.append ({b});
    assert (!queue.undo_clear ());
    assert (queue.remove (0));
    assert (queue.current == b);
    assert (queue.remove (0));
    assert (queue.current == null && queue.index == -1);
    queue.append ({a, b});
    queue.clear ();
    assert (queue.entries.length == 0);
    queue.undo_clear ();
    assert (queue.entries.length == 2 && queue.current == null);
}

void test_session () {
    try {
        var queue = new PlayQueue ();
        var track = new Track ("smb://nas.local/music/song.flac", "Canción");
        track.artist = "Artista";
        track.album = "Álbum";
        track.number = 2;
        track.duration = 400 * Gst.SECOND;
        queue.append ({track, track});
        queue.select (1);
        var saved = QueueSession.decode (new QueueSession.capture (queue, 42.25).encode ());
        var restored = new PlayQueue ();
        restored.restore (saved.entries, saved.current_id);
        assert (restored.entries.length == 2 && restored.index == 1);
        assert (restored.current_entry.id == queue.current_entry.id);
        assert (restored.entries[0].id != restored.entries[1].id);
        assert (restored.current.title == "Canción" && restored.current.number == 2);
        assert (saved.position == 42.25);
        bool invalid = false;
        try { QueueSession.decode ("bad data"); } catch (Error e) { invalid = true; }
        assert (invalid);
        track.uri = "smb://name:password@nas.local/song.flac";
        invalid = false;
        try { new QueueSession.capture (queue, 0).encode (); } catch (Error e) { invalid = true; }
        assert (invalid);
        string path = fixture + "/session.ini";
        var store = new SessionStore (path);
        store.failure.connect ((message) => { error ("Sesión: %s", message); });
        track.uri = "file:///song.flac";
        store.save (new QueueSession.capture (queue, 1));
        store.save (new QueueSession.capture (queue, 2));
        var loop = new MainLoop ();
        store.flush.begin (() => { loop.quit (); });
        loop.run ();
        string data;
        FileUtils.get_contents (path, out data);
        assert (QueueSession.decode (data).position == 2);
        FileUtils.set_contents (path, "corrupt");
        store.load.begin ((obj, res) => {
            assert (store.load.end (res).entries.length == 0);
            loop.quit ();
        });
        loop.run ();
    } catch (Error e) { error ("Sesión: %s", e.message); }
}

void test_playback_queue_edit () {
    var queue = new PlayQueue ();
    var a = new Track (File.new_for_path (fixture + "/nested/song.flac").get_uri (), "A");
    queue.append ({a, a, a});
    queue.select (1);
    var sink = Gst.ElementFactory.make ("fakesink", null);
    sink.set ("sync", true);
    var player = new Player (queue, sink);
    var loop = new MainLoop ();
    bool checked = false;
    bool editing = false;
    player.changed.connect (() => {
        if (editing || checked || player.state != Gst.State.PLAYING) return;
        editing = true;
        assert (player.seek (0.1));
        Timeout.add (40, () => {
        string id = queue.current_entry.id;
        queue.move (1, 0);
        queue.append ({a});
        queue.remove (2);
        queue.clear ();
        queue.undo_clear ();
        assert (queue.current_entry.id == id && player.state == Gst.State.PLAYING);
        assert (player.position () >= 0.09);
        player.stop_after_current = true;
        player.pause ();
        assert (player.stop_after_current);
        checked = true;
        loop.quit ();
        return Source.REMOVE;
        });
    });
    uint timeout = Timeout.add_seconds (3, () => { loop.quit (); return Source.REMOVE; });
    player.play ();
    loop.run ();
    if (checked) Source.remove (timeout);
    assert (checked);
    player.activate (queue.index);
    assert (!player.stop_after_current);
    player.stop_after_current = true;
    player.stop ();
    assert (!player.stop_after_current);
    player.shutdown ();
}

void test_stop_after_current () {
    var queue = new PlayQueue ();
    var track = new Track (File.new_for_path (fixture + "/nested/song.flac").get_uri (), "A");
    queue.append ({track, track});
    queue.select (0);
    var sink = Gst.ElementFactory.make ("fakesink", null);
    sink.set ("sync", true);
    var player = new Player (queue, sink);
    var loop = new MainLoop ();
    bool finished = false;
    player.finished.connect (() => { finished = true; loop.quit (); });
    uint timeout = Timeout.add_seconds (3, () => { loop.quit (); return Source.REMOVE; });
    player.stop_after_current = true;
    player.play ();
    loop.run ();
    if (finished) Source.remove (timeout);
    assert (finished && queue.index == 0 && player.state == Gst.State.NULL);
    assert (!player.stop_after_current);
    player.shutdown ();
}

void test_import_batch () {
    try {
        string folder = fixture + "/import";
        DirUtils.create (folder, 0700);
        string original = fixture + "/nested/song.flac";
        string[] command = {"ffmpeg", "-v", "error", "-i", original, "-c", "copy", "-metadata", "track=1", "-y", folder + "/first.flac"};
        int status;
        Process.spawn_sync (null, command, null, SpawnFlags.SEARCH_PATH, null, null, null, out status);
        assert (status == 0);
        File.new_for_path (original).copy (File.new_for_path (folder + "/second.flac"), FileCopyFlags.OVERWRITE);
        FileUtils.set_contents (folder + "/broken.flac", "invalid audio");
        File.new_for_path (folder + "/link.flac").make_symbolic_link (original);
        File.new_for_path (folder + "/loop").make_symbolic_link (folder);
        var scanner = new Music.Scanner ();
        var loop = new MainLoop ();
        bool responsive = false;
        Idle.add (() => { responsive = true; return Source.REMOVE; });
        scanner.import_sources.begin ({File.new_for_path (original), File.new_for_path (folder), File.new_for_path (fixture + "/notes.txt")}, new Cancellable (), (obj, res) => {
            try {
                var imported = scanner.import_sources.end (res);
                assert (responsive);
                assert (imported.length == 3 && scanner.skipped == 2);
                assert (imported[0].uri.has_suffix ("/nested/song.flac"));
                assert (imported[1].number == 1 && imported[2].number == 2);
            } catch (Error e) { error ("Importación: %s", e.message); }
            loop.quit ();
        });
        loop.run ();
        var cancel = new Cancellable ();
        cancel.cancel ();
        scanner.import_sources.begin ({File.new_for_path (folder)}, cancel, (obj, res) => {
            bool cancelled = false;
            try { scanner.import_sources.end (res); } catch (IOError.CANCELLED e) { cancelled = true; }
            catch (Error e) { error ("%s", e.message); }
            assert (cancelled);
            loop.quit ();
        });
        loop.run ();
        scanner.import_sources.begin ({File.new_for_path (original), File.new_for_path (folder + "/absent")}, new Cancellable (), (obj, res) => {
            bool failed = false;
            try { scanner.import_sources.end (res); } catch (Error e) { failed = true; }
            assert (failed); // No partial batch is delivered when a requested source fails.
            loop.quit ();
        });
        loop.run ();
    } catch (Error e) { error ("Importación: %s", e.message); }
}

void test_restore_playback_position () {
    var queue = new PlayQueue ();
    queue.append ({new Track (File.new_for_path (fixture + "/nested/song.flac").get_uri (), "A")});
    queue.select (0);
    var sink = Gst.ElementFactory.make ("fakesink", null);
    sink.set ("sync", true);
    var player = new Player (queue, sink);
    player.restore_position (0.2);
    assert (player.state == Gst.State.NULL && player.saved_position == 0.2);
    var loop = new MainLoop ();
    bool restored = false;
    player.changed.connect (() => {
        if (player.state == Gst.State.PLAYING && player.position () >= 0.18) { restored = true; loop.quit (); }
    });
    uint timeout = Timeout.add_seconds (3, () => { loop.quit (); return Source.REMOVE; });
    player.play ();
    loop.run ();
    if (restored) Source.remove (timeout);
    assert (restored);
    player.shutdown ();
}

void test_remove_current_paused () {
    var queue = new PlayQueue ();
    var track = new Track (File.new_for_path (fixture + "/nested/song.flac").get_uri (), "A");
    queue.append ({track, track, track});
    queue.select (0);
    var sink = Gst.ElementFactory.make ("fakesink", null);
    sink.set ("sync", true);
    var player = new Player (queue, sink);
    var loop = new MainLoop ();
    int stage = 0;
    bool completed = false;
    player.changed.connect (() => {
        if (stage == 0 && player.state == Gst.State.PLAYING) { stage = 1; player.pause (); }
        else if (stage == 1 && player.state == Gst.State.PAUSED) {
            stage = 2;
            queue.remove (queue.index);
        } else if (stage == 2 && player.state == Gst.State.PAUSED) {
            completed = true;
            loop.quit ();
        }
    });
    uint timeout = Timeout.add_seconds (3, () => { loop.quit (); return Source.REMOVE; });
    player.play ();
    loop.run ();
    if (completed) Source.remove (timeout);
    assert (completed && queue.entries.length == 2 && queue.index == 0);
    assert (player.state == Gst.State.PAUSED);
    player.stop ();
    queue.remove (0);
    assert (queue.current != null && player.state == Gst.State.NULL);
    queue.remove (0);
    assert (queue.current == null && player.state == Gst.State.NULL);
    player.shutdown ();
}

void test_visualizer_audio_branch () {
    // A real 48 kHz stereo source: the analysis branch must not resample output.
    try {
        string audio = fixture + "/tap.wav";
        string[] command = {"ffmpeg", "-v", "error", "-f", "lavfi", "-i",
            "sine=frequency=220:duration=2", "-ar", "48000", "-ac", "2", "-y", audio};
        int status;
        Process.spawn_sync (null, command, null, SpawnFlags.SEARCH_PATH, null, null, null, out status);
        assert (status == 0);
        var queue = new PlayQueue ();
        queue.append ({new Track (File.new_for_path (audio).get_uri (), "Audio")});
        queue.select (0);
        var sink = Gst.ElementFactory.make ("fakesink", null);
        sink.set ("sync", true);
        var player = new Player (queue, sink);
        assert (player.visualization.available);
        player.visualization.enable (true);
        bool received = false;
        bool finished = false;
        bool failed = false;
        var loop = new MainLoop ();
        player.failure.connect (() => { failed = true; loop.quit (); });
        player.finished.connect (() => { finished = true; loop.quit (); });
        uint poll = Timeout.add (20, () => {
            var pcm = player.visualization.read ();
            if (pcm.length == 0) return Source.CONTINUE;
            assert (pcm.length % 8 == 0);
            bool nonzero = false;
            foreach (uint8 value in pcm) if (value != 0) nonzero = true;
            assert (nonzero);
            var caps = sink.get_static_pad ("sink").get_current_caps ();
            assert (caps != null);
            int rate, channels;
            assert (caps.get_structure (0).get_int ("rate", out rate) && rate == 48000);
            assert (caps.get_structure (0).get_int ("channels", out channels) && channels == 2);
            received = true;
            player.visualization.enable (false);
            assert (player.visualization.read ().length == 0);
            return Source.CONTINUE;
        });
        uint timeout = Timeout.add_seconds (5, () => { loop.quit (); return Source.REMOVE; });
        player.play ();
        loop.run ();
        Source.remove (poll);
        if (finished || failed) Source.remove (timeout);
        assert (received && finished && !failed);
        player.shutdown ();
        FileUtils.unlink (audio);
    } catch (Error e) { error ("%s", e.message); }
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
    Test.add_func ("/library/cache-roundtrip", givenTwoCachedTracks_whenCacheIsReopened_thenTracksAndMetadataArePreserved);
    Test.add_func ("/library/cache-shared-artwork", givenTracksSharingArtwork_whenCacheIsReopened_thenArtworkIsStoredAndLoadedOnce);
    Test.add_func ("/library/persisted-incremental-reconciliation", givenPersistedLibrary_whenFilesChange_thenOnlyNewAndModifiedAudioAreDiscovered);
    Test.add_func ("/library/cached-track-transient-failure", givenCachedTrack_whenChangedAudioCannotBeRead_thenKnownMetadataIsRetained);
    Test.add_func ("/library/cached-folder-cover-change", givenCachedAudio_whenFolderCoverChanges_thenArtworkRefreshesWithoutRediscoveringAudio);
    Test.add_func ("/queue/navigation-boundaries", test_queue);
    Test.add_func ("/import/ordered-cancellable-atomic-batch", test_import_batch);
    Test.add_func ("/player/restored-position-after-preroll", test_restore_playback_position);
    Test.add_func ("/player/remove-current-preserves-paused-state", test_remove_current_paused);
    Test.add_func ("/queue/edit-identity-clear-undo", test_queue_edits);
    Test.add_func ("/session/roundtrip-corruption-coalesced-writes", test_session);
    Test.add_func ("/player/queue-edit-preserves-audio", test_playback_queue_edit);
    Test.add_func ("/player/stop-after-current", test_stop_after_current);
    Test.add_func ("/player/eos-next-and-finish", test_playback_eos);
    Test.add_func ("/player/pause-seek-volume", test_player_controls);
    Test.add_func ("/player/error-does-not-skip", test_player_error);
    Test.add_func ("/player/visualizer-pcm-preserves-output-and-eos", test_visualizer_audio_branch);
    int status = Test.run ();
    FileUtils.unlink (fixture + "/alias.flac");
    FileUtils.unlink (fixture + "/loop");
    FileUtils.unlink (fixture + "/notes.txt");
    FileUtils.unlink (fixture + "/nested/song.flac");
    DirUtils.remove (fixture + "/nested");
    DirUtils.remove (fixture);
    return status;
}
