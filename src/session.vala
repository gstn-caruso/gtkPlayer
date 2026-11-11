namespace Music {
    // A separate, versioned session contains metadata only. Never probe or mount sources.
    public class QueueSession : Object {
        public QueueEntry[] entries = {};
        public string? current_id;
        public double position;
        public QueueSession.capture (PlayQueue queue, double position) {
            QueueEntry[] snapshot = {};
            foreach (var entry in queue.entries) snapshot += new QueueEntry (entry.track.copy (), entry.id);
            entries = snapshot;
            current_id = queue.current_entry == null ? null : queue.current_entry.id;
            this.position = double.max (0, position);
        }
        public QueueSession () { }
        public string encode () throws Error {
            var key = new KeyFile ();
            key.set_integer ("session", "version", 1);
            key.set_integer ("session", "count", entries.length);
            key.set_string ("session", "current", current_id ?? "");
            key.set_double ("session", "position", position);
            for (int i = 0; i < entries.length; i++) {
                string group = "entry-" + i.to_string ();
                var entry = entries[i];
                var track = entry.track;
                LocationSettings.parse_location (track.uri); // reject credentials and other schemes
                key.set_string (group, "id", entry.id);
                key.set_string (group, "uri", track.uri);
                key.set_string (group, "title", track.title);
                key.set_string (group, "artist", track.artist);
                key.set_string (group, "album", track.album);
                key.set_uint64 (group, "number", track.number);
                key.set_uint64 (group, "duration", track.duration);
                track.write_audio_info (key, group);
            }
            return key.to_data ();
        }
        public static QueueSession decode (string data) throws Error {
            var key = new KeyFile ();
            key.load_from_data (data, data.length, KeyFileFlags.NONE);
            if (key.get_integer ("session", "version") != 1) throw new IOError.INVALID_DATA ("Versión de sesión desconocida");
            int count = key.get_integer ("session", "count");
            if (count < 0 || count > 100000) throw new IOError.INVALID_DATA ("Cola inválida");
            var result = new QueueSession ();
            var ids = new HashTable<string, bool> (str_hash, str_equal);
            QueueEntry[] restored = {};
            for (int i = 0; i < count; i++) {
                string group = "entry-" + i.to_string ();
                string id = key.get_string (group, "id");
                if (id == "" || ids.contains (id)) throw new IOError.INVALID_DATA ("Identidad de entrada inválida");
                ids.insert (id, true);
                var uri = LocationSettings.parse_location (key.get_string (group, "uri")).get_uri ();
                var track = new Track (uri, key.get_string (group, "title"));
                track.artist = key.get_string (group, "artist");
                track.album = key.get_string (group, "album");
                track.number = (uint) key.get_uint64 (group, "number");
                track.duration = key.get_uint64 (group, "duration");
                track.read_audio_info (key, group);
                restored += new QueueEntry (track, id);
            }
            result.entries = restored;
            string current = key.get_string ("session", "current");
            if (current != "" && !ids.contains (current)) throw new IOError.INVALID_DATA ("Entrada actual ausente");
            result.current_id = current == "" ? null : current;
            result.position = key.get_double ("session", "position");
            if (!result.position.is_finite () || result.position < 0) throw new IOError.INVALID_DATA ("Posición inválida");
            return result;
        }
    }

    public class SessionStore : Object {
        private string path;
        private QueueSession? pending;
        private bool writing;
        public signal void failure (string message);
        public SessionStore (string path) { this.path = path; }
        public async QueueSession load () {
            QueueSession result = new QueueSession ();
            new Thread<void*> ("session-read", () => {
                try {
                    string data;
                    FileUtils.get_contents (path, out data);
                    result = QueueSession.decode (data);
                } catch (Error e) { /* Missing/corrupt session opens an empty queue. */ }
                Idle.add (() => { load.callback (); return Source.REMOVE; });
                return null;
            });
            yield;
            return result;
        }
        // One writer; coalesce frequent progress snapshots without stale writes winning.
        public void save (QueueSession snapshot) {
            pending = snapshot;
            if (!writing) write_pending.begin ();
        }
        private async void write_pending () {
            writing = true;
            while (pending != null) {
                var snapshot = pending;
                pending = null;
                Error? problem = null;
                new Thread<void*> ("session-write", () => {
                    try {
                        if (DirUtils.create_with_parents (Path.get_dirname (path), 0700) != 0)
                            throw new IOError.FAILED ("No se pudo crear la carpeta de sesión");
                        string data = snapshot.encode ();
                        File.new_for_path (path).replace_contents (data.data, null, false, FileCreateFlags.PRIVATE, null);
                    } catch (Error e) { problem = e; }
                    Idle.add (() => { write_pending.callback (); return Source.REMOVE; });
                    return null;
                });
                yield;
                if (problem != null) failure (problem.message);
            }
            writing = false;
        }
        public async void flush () {
            while (writing) {
                Timeout.add (10, () => { flush.callback (); return Source.REMOVE; });
                yield;
            }
        }
    }
}
