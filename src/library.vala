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
        public Track (string uri, string title) {
            this.uri = uri;
            this.title = title;
        }
    }

    public class Scanner : Object {
        public uint skipped { get; private set; default = 0; }

        public async Track[] scan (File folder, Cancellable cancel) throws Error {
            Track[] tracks = {};
            Error? failure = null;
            skipped = 0;
            new Thread<void*> ("library-scan", () => {
                try {
                    var discoverer = new Gst.PbUtils.Discoverer (5 * Gst.SECOND);
                    tracks = walk (folder, cancel, discoverer);
                } catch (Error e) { failure = e; }
                Idle.add (() => { scan.callback (); return Source.REMOVE; });
                return null;
            });
            yield;
            if (failure != null) throw failure;
            cancel.set_error_if_cancelled ();
            return tracks;
        }

        private Track[] walk (File folder, Cancellable cancel, Gst.PbUtils.Discoverer discoverer) throws Error {
            Track[] tracks = {};
            cancel.set_error_if_cancelled ();
            var children = folder.enumerate_children ("standard::name,standard::type,standard::is-symlink",
                FileQueryInfoFlags.NOFOLLOW_SYMLINKS, cancel);
            FileInfo? info;
            while ((info = children.next_file (cancel)) != null) {
                cancel.set_error_if_cancelled ();
                if (info.get_is_symlink ()) continue;
                var child = children.get_child (info);
                if (info.get_file_type () == FileType.DIRECTORY) {
                    foreach (var track in walk (child, cancel, discoverer)) tracks += track;
                } else if (info.get_file_type () == FileType.REGULAR && is_audio (info.get_name ())) {
                    try {
                        var discovered = discoverer.discover_uri (playable_uri (child.get_uri ()));
                        if (discovered.get_result () != Gst.PbUtils.DiscovererResult.OK ||
                            discovered.get_audio_streams ().length () == 0) {
                            skipped++;
                            continue;
                        }
                        string name = info.get_name ();
                        int dot = name.last_index_of (".");
                        var track = new Track (child.get_uri (), dot > 0 ? name.substring (0, dot) : name);
                        track.duration = discovered.get_duration ();
                        var stream = discovered.get_stream_info ();
                        if (stream is Gst.PbUtils.DiscovererContainerInfo)
                            read_tags (track, ((Gst.PbUtils.DiscovererContainerInfo) stream).get_tags ());
                        foreach (var audio in discovered.get_audio_streams ()) read_tags (track, audio.get_tags ());
                        tracks += track;
                    } catch (Error e) { skipped++; }
                }
            }
            children.close (cancel);
            return tracks;
        }

        private bool is_audio (string name) {
            string lower = name.down ();
            foreach (string extension in new string[] {".flac", ".mp3", ".ogg", ".opus", ".wav", ".m4a", ".aac", ".wma", ".aiff"})
                if (lower.has_suffix (extension)) return true;
            return false;
        }

        private void read_tags (Track track, Gst.TagList? tags) {
            if (tags == null) return;
            string value;
            uint number;
            if (tags.get_string (Gst.Tags.TITLE, out value)) track.title = value;
            if (tags.get_string (Gst.Tags.ARTIST, out value)) track.artist = value;
            if (tags.get_string (Gst.Tags.ALBUM, out value)) track.album = value;
            if (tags.get_uint (Gst.Tags.TRACK_NUMBER, out number)) track.number = number;
        }
    }
}
