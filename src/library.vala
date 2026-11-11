namespace Music {
    // GIO preserves the source URI; mounted GVfs paths are used only at the media boundary.
    public string playable_uri (string uri) {
        var file = File.new_for_uri (uri);
        string? path = file.get_path ();
        return path != null ? File.new_for_path (path).get_uri () : uri;
    }

    public class Track : Object {
        public string uri;
        public string title;
        public string artist = "Artista desconocido";
        public string album = "Sin álbum";
        public uint number = 0;
        public uint64 duration = 0;
        public Bytes? cover_data;
        internal string cover_origin = "embedded";
        internal int64 cover_size = -1;
        internal uint64 cover_modified_time;
        internal uint32 cover_modified_usec;
        internal bool has_fingerprint = false;
        internal int64 file_size;
        internal uint64 modified_time;
        internal uint32 modified_usec;
        public Track (string uri, string title) {
            this.uri = uri;
            this.title = title;
        }

        internal Track copy () {
            var track = new Track (uri, title);
            track.artist = artist;
            track.album = album;
            track.number = number;
            track.duration = duration;
            // Bytes is immutable: preserve artwork without copying or encoding it.
            track.cover_data = cover_data;
            track.cover_origin = cover_origin;
            track.cover_size = cover_size;
            track.cover_modified_time = cover_modified_time;
            track.cover_modified_usec = cover_modified_usec;
            track.has_fingerprint = has_fingerprint;
            track.file_size = file_size;
            track.modified_time = modified_time;
            track.modified_usec = modified_usec;
            return track;
        }
    }

    public class LibraryCache : Object {
        private string path;

        public LibraryCache (string path) {
            this.path = path;
        }

        private File source_file (string source_uri) {
            string name = Checksum.compute_for_string (ChecksumType.SHA256, source_uri);
            return File.new_for_path (Path.build_filename (path, name + ".ini"));
        }

        internal static bool same_contents (Track[] previous, Track[] tracks, Cancellable cancel) throws Error {
            cancel.set_error_if_cancelled ();
            if (previous.length != tracks.length) return false;
            var known = new HashTable<string, Track> (str_hash, str_equal);
            foreach (var track in previous) known.insert (track.uri, track);
            foreach (var track in tracks) {
                cancel.set_error_if_cancelled ();
                var before = known.lookup (track.uri);
                if (before == null || track.title != before.title || track.artist != before.artist ||
                    track.album != before.album || track.number != before.number ||
                    track.duration != before.duration || track.has_fingerprint != before.has_fingerprint ||
                    track.cover_origin != before.cover_origin) return false;
                if (track.has_fingerprint && (track.file_size != before.file_size ||
                    track.modified_time != before.modified_time || track.modified_usec != before.modified_usec)) return false;
                if (track.cover_origin == "folder" && (track.cover_size != before.cover_size ||
                    track.cover_modified_time != before.cover_modified_time ||
                    track.cover_modified_usec != before.cover_modified_usec)) return false;
                if (track.cover_data != before.cover_data && (track.cover_data == null ||
                    before.cover_data == null || track.cover_data.compare (before.cover_data) != 0)) return false;
            }
            return true;
        }

        public void save (string source_uri, Track[] tracks, Cancellable? cancel = null) throws Error {
            if (cancel != null) cancel.set_error_if_cancelled ();
            var cache = new KeyFile ();
            cache.set_integer ("library", "count", tracks.length);
            var covers = new HashTable<string, Bytes> (str_hash, str_equal);
            for (int i = 0; i < tracks.length; i++) {
                string group = "track-" + i.to_string ();
                var track = tracks[i];
                cache.set_string (group, "uri", track.uri);
                cache.set_string (group, "title", track.title);
                cache.set_string (group, "artist", track.artist);
                cache.set_string (group, "album", track.album);
                cache.set_uint64 (group, "number", track.number);
                cache.set_uint64 (group, "duration", track.duration);
                if (track.has_fingerprint) {
                    cache.set_int64 (group, "file-size", track.file_size);
                    cache.set_uint64 (group, "modified-time", track.modified_time);
                    cache.set_uint64 (group, "modified-usec", track.modified_usec);
                }
                cache.set_string (group, "cover-origin", track.cover_origin);
                if (track.cover_origin == "folder") {
                    cache.set_int64 (group, "cover-size", track.cover_size);
                    cache.set_uint64 (group, "cover-modified-time", track.cover_modified_time);
                    cache.set_uint64 (group, "cover-modified-usec", track.cover_modified_usec);
                }
                if (track.cover_data != null) {
                    string hash = Checksum.compute_for_bytes (ChecksumType.SHA256, track.cover_data);
                    string id = hash;
                    int suffix = 0;
                    while (covers.contains (id) && covers.lookup (id).compare (track.cover_data) != 0)
                        id = hash + "-" + (++suffix).to_string ();
                    if (!covers.contains (id)) {
                        covers.insert (id, track.cover_data);
                        cache.set_string ("cover-" + id, "data", Base64.encode (track.cover_data.get_data ()));
                    }
                    cache.set_string (group, "cover-ref", id);
                }
            }
            try {
                File.new_for_path (path).make_directory_with_parents (cancel);
            } catch (IOError.EXISTS e) {
                // The cache directory can already exist when saving again.
            }
            string data = cache.to_data ();
            source_file (source_uri).replace_contents (data.data, null, false,
                FileCreateFlags.PRIVATE, null, cancel);
        }

        public Track[] load (string source_uri) throws Error {
            var cache = new KeyFile ();
            cache.load_from_file (source_file (source_uri).get_path (), KeyFileFlags.NONE);
            Track[] tracks = {};
            var covers = new HashTable<string, Bytes> (str_hash, str_equal);
            int count = cache.get_integer ("library", "count");
            for (int i = 0; i < count; i++) {
                string group = "track-" + i.to_string ();
                var track = new Track (cache.get_string (group, "uri"), cache.get_string (group, "title"));
                track.artist = cache.get_string (group, "artist");
                track.album = cache.get_string (group, "album");
                track.number = (uint) cache.get_uint64 (group, "number");
                track.duration = cache.get_uint64 (group, "duration");
                if (cache.has_key (group, "file-size") &&
                    cache.has_key (group, "modified-time") && cache.has_key (group, "modified-usec")) {
                    track.file_size = cache.get_int64 (group, "file-size");
                    track.modified_time = cache.get_uint64 (group, "modified-time");
                    track.modified_usec = (uint32) cache.get_uint64 (group, "modified-usec");
                    track.has_fingerprint = true;
                }
                if (cache.has_key (group, "cover-origin")) {
                    track.cover_origin = cache.get_string (group, "cover-origin");
                    if (track.cover_origin == "folder") {
                        track.cover_size = cache.get_int64 (group, "cover-size");
                        track.cover_modified_time = cache.get_uint64 (group, "cover-modified-time");
                        track.cover_modified_usec = (uint32) cache.get_uint64 (group, "cover-modified-usec");
                    }
                }
                if (cache.has_key (group, "cover-ref")) {
                    string id = cache.get_string (group, "cover-ref");
                    var cover = covers.lookup (id);
                    if (cover == null) {
                        cover = new Bytes (Base64.decode (cache.get_string ("cover-" + id, "data")));
                        covers.insert (id, cover);
                    }
                    track.cover_data = cover;
                } else if (cache.has_key (group, "cover")) {
                    track.cover_data = new Bytes (Base64.decode (cache.get_string (group, "cover")));
                }
                tracks += track;
            }
            return tracks;
        }
    }

    private class FolderCover : Object {
        private File file;
        private bool queried = false;
        private bool available = false;
        private bool loaded = false;
        private FileInfo? info;
        private Bytes? data;

        public FolderCover (File folder) {
            file = folder.get_child ("cover.jpg");
        }

        public void refresh (Track track, Cancellable cancel) {
            if (track.cover_data != null && track.cover_origin != "folder") return;
            if (!queried) {
                queried = true;
                try {
                    info = file.query_info ("standard::type,standard::is-symlink,standard::size,time::modified,time::modified-usec",
                        FileQueryInfoFlags.NOFOLLOW_SYMLINKS, cancel);
                    available = true;
                } catch (IOError.NOT_FOUND e) {
                    available = true;
                } catch (Error e) {
                    // A transient error must not replace known artwork.
                }
            }
            if (!available) return;
            if (info == null || info.get_file_type () != FileType.REGULAR || Scanner.is_symbolic_link (info)) {
                track.cover_data = null;
                track.cover_origin = "folder";
                track.cover_size = -1;
                track.cover_modified_time = 0;
                track.cover_modified_usec = 0;
                return;
            }
            int64 size = info.has_attribute (FileAttribute.STANDARD_SIZE) &&
                info.has_attribute (FileAttribute.TIME_MODIFIED) ? info.get_size () : -1;
            uint64 modified = info.get_attribute_uint64 (FileAttribute.TIME_MODIFIED);
            uint32 usec = info.get_attribute_uint32 (FileAttribute.TIME_MODIFIED_USEC);
            if (track.cover_origin == "folder" && track.cover_data != null && size >= 0 &&
                track.cover_size == size && track.cover_modified_time == modified &&
                track.cover_modified_usec == usec) return;
            if (!loaded) {
                loaded = true;
                try {
                    data = file.load_bytes (cancel, null);
                } catch (Error e) {
                    // Retain the old bytes and fingerprint so the next scan retries.
                }
            }
            if (data == null) return;
            track.cover_data = data;
            track.cover_origin = "folder";
            track.cover_size = size;
            track.cover_modified_time = modified;
            track.cover_modified_usec = usec;
        }
    }

    public class Scanner : Object {
        public uint skipped { get; private set; default = 0; }
        public uint discovered { get; private set; default = 0; }
        // Includes empty directories; published only after the worker has finished.
        private File[] directories = {};
        public unowned File[] get_directories () { return directories; }

        public async Track[] scan (File folder, Cancellable cancel, Track[] previous = {}) throws Error {
            Track[] tracks = {};
            Error? failure = null;
            skipped = 0;
            discovered = 0;
            directories = {};
            var known = new HashTable<string, Track> (str_hash, str_equal);
            // Reused tracks are mutable; keep the persisted/displayed baseline intact.
            foreach (var track in previous) known.insert (track.uri, track.copy ());
            new Thread<void*> ("library-scan", () => {
                try {
                    var discoverer = new Gst.PbUtils.Discoverer (5 * Gst.SECOND);
                    tracks = walk (folder, cancel, discoverer, known);
                } catch (Error e) { failure = e; }
                Idle.add (() => { scan.callback (); return Source.REMOVE; });
                return null;
            });
            yield;
            if (failure != null) throw failure;
            cancel.set_error_if_cancelled ();
            return tracks;
        }

        private Track[] walk (File folder, Cancellable cancel, Gst.PbUtils.Discoverer discoverer,
                              HashTable<string, Track> known) throws Error {
            Track[] tracks = {};
            cancel.set_error_if_cancelled ();
            var children = folder.enumerate_children ("standard::name,standard::type,standard::is-symlink,standard::size,time::modified,time::modified-usec",
                FileQueryInfoFlags.NOFOLLOW_SYMLINKS, cancel);
            FileInfo? info;
            var folder_cover = new FolderCover (folder);
            while ((info = children.next_file (cancel)) != null) {
                cancel.set_error_if_cancelled ();
                if (is_symbolic_link (info)) continue;
                var child = children.get_child (info);
                if (info.get_file_type () == FileType.DIRECTORY) {
                    foreach (var track in walk (child, cancel, discoverer, known)) tracks += track;
                } else if (info.get_file_type () == FileType.REGULAR && is_audio (info.get_name ())) {
                    var track = inspect_audio (child, info, folder_cover, cancel, discoverer, known);
                    if (track != null) tracks += track;
                }
            }
            children.close (cancel);
            directories += folder;
            return tracks;
        }

        private Track? inspect_audio (File child, FileInfo info, FolderCover folder_cover, Cancellable cancel,
                                      Gst.PbUtils.Discoverer discoverer, HashTable<string, Track> known) {
            var cached = known.lookup (child.get_uri ());
            bool has_fingerprint = info.has_attribute (FileAttribute.STANDARD_SIZE) &&
                info.has_attribute (FileAttribute.TIME_MODIFIED);
            int64 file_size = info.get_size ();
            uint64 modified_time = info.get_attribute_uint64 (FileAttribute.TIME_MODIFIED);
            uint32 modified_usec = info.get_attribute_uint32 (FileAttribute.TIME_MODIFIED_USEC);
            if (cached != null && cached.has_fingerprint && has_fingerprint &&
                cached.file_size == file_size && cached.modified_time == modified_time &&
                cached.modified_usec == modified_usec) {
                folder_cover.refresh (cached, cancel);
                return cached;
            }
            try {
                this.discovered++;
                var discovered = discoverer.discover_uri (playable_uri (child.get_uri ()));
                if (discovered.get_result () != Gst.PbUtils.DiscovererResult.OK ||
                    discovered.get_audio_streams ().length () == 0) {
                    skipped++;
                    if (cached != null) {
                        cached.has_fingerprint = false;
                    }
                    return cached;
                }
                string name = info.get_name ();
                int dot = name.last_index_of (".");
                var track = new Track (child.get_uri (), dot > 0 ? name.substring (0, dot) : name);
                track.has_fingerprint = has_fingerprint;
                track.file_size = file_size;
                track.modified_time = modified_time;
                track.modified_usec = modified_usec;
                track.duration = discovered.get_duration ();
                read_tags (track, discovered.get_tags ());
                var stream = discovered.get_stream_info ();
                if (stream is Gst.PbUtils.DiscovererContainerInfo)
                    read_tags (track, ((Gst.PbUtils.DiscovererContainerInfo) stream).get_tags ());
                foreach (var audio in discovered.get_audio_streams ()) read_tags (track, audio.get_tags ());
                if (track.cover_data == null) {
                    if (cached != null && cached.cover_origin == "folder") {
                        track.cover_data = cached.cover_data;
                        track.cover_origin = cached.cover_origin;
                        track.cover_size = cached.cover_size;
                        track.cover_modified_time = cached.cover_modified_time;
                        track.cover_modified_usec = cached.cover_modified_usec;
                    }
                    folder_cover.refresh (track, cancel);
                }
                return track;
            } catch (Error e) {
                skipped++;
                if (cached != null) {
                    cached.has_fingerprint = false;
                    return cached;
                }
            }

            return null;
        }

        public static int compare_tracks (Track a, Track b) {
            int order = a.artist.collate (b.artist);
            if (order == 0) order = strcmp (a.artist, b.artist);
            if (order == 0) order = a.album.collate (b.album);
            if (order == 0) order = strcmp (a.album, b.album);
            if (order == 0) order = a.number < b.number ? -1 : a.number > b.number ? 1 : 0;
            if (order == 0) order = a.title.collate (b.title);
            return order == 0 ? strcmp (a.uri, b.uri) : order;
        }

        public async Track[] import_sources (File[] sources, Cancellable cancel) throws Error {
            File[] inputs = {};
            foreach (var source in sources) inputs += source;
            Track[] imported = {};
            Error? failure = null;
            skipped = 0;
            new Thread<void*> ("queue-import", () => {
                try {
                    var discoverer = new Gst.PbUtils.Discoverer (5 * Gst.SECOND);
                    var known = new HashTable<string, Track> (str_hash, str_equal);
                    foreach (var input in inputs) {
                        cancel.set_error_if_cancelled ();
                        var source = LocationSettings.parse_location (input.get_uri ());
                        var info = source.query_info ("standard::name,standard::type,standard::is-symlink,standard::size,time::modified,time::modified-usec",
                            FileQueryInfoFlags.NOFOLLOW_SYMLINKS, cancel);
                        if (is_symbolic_link (info)) { skipped++; continue; }
                        if (info.get_file_type () == FileType.DIRECTORY) {
                            var sorted = new List<Track> ();
                            foreach (var track in walk (source, cancel, discoverer, known)) sorted.append (track);
                            sorted.sort (compare_tracks);
                            foreach (var track in sorted) imported += track;
                        } else if (info.get_file_type () == FileType.REGULAR && is_audio (info.get_name ())) {
                            var track = inspect_audio (source, info, new FolderCover (source.get_parent ()), cancel, discoverer, known);
                            if (track != null) imported += track;
                        } else skipped++;
                    }
                    cancel.set_error_if_cancelled ();
                } catch (Error e) { failure = e; }
                Idle.add (() => { import_sources.callback (); return Source.REMOVE; });
                return null;
            });
            yield;
            if (failure != null) throw failure;
            cancel.set_error_if_cancelled ();
            return imported;
        }

        internal static bool is_symbolic_link (FileInfo info) {
            return info.get_file_type () == FileType.SYMBOLIC_LINK ||
                (info.has_attribute (FileAttribute.STANDARD_IS_SYMLINK) && info.get_is_symlink ());
        }

        internal static bool is_audio (string name) {
            string lower = name.down ();
            foreach (string extension in new string[] {".flac", ".mp3", ".ogg", ".opus", ".wav", ".m4a", ".aac", ".wma", ".aiff"})
                if (lower.has_suffix (extension)) return true;
            return false;
        }

        private static void read_tags (Track track, Gst.TagList? tags) {
            if (tags == null) return;
            string value;
            uint number;
            if (tags.get_string (Gst.Tags.TITLE, out value)) track.title = value;
            if (tags.get_string (Gst.Tags.ARTIST, out value)) track.artist = value;
            if (tags.get_string (Gst.Tags.ALBUM, out value)) track.album = value;
            if (tags.get_uint (Gst.Tags.TRACK_NUMBER, out number)) track.number = number;
            if (track.cover_data == null) {
                Gst.Sample sample;
                if (tags.get_sample (Gst.Tags.IMAGE, out sample) ||
                    tags.get_sample (Gst.Tags.PREVIEW_IMAGE, out sample)) {
                    var buffer = sample.get_buffer ();
                    if (buffer != null && buffer.get_size () > 0) {
                        uint8[] data;
                        buffer.extract_dup (0, buffer.get_size (), out data);
                        track.cover_data = new Bytes (data);
                    }
                }
            }
        }
    }
}
