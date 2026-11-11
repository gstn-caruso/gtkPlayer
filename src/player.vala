namespace Music {
    public class Player : Object {
        public PlayQueue queue { get; construct; }
        public Gst.State state { get; private set; default = Gst.State.NULL; }
        public signal void changed ();
        public signal void failure (string message);
        public signal void finished ();
        private Gst.Element? pipeline;
        private uint watch;
        private string? loaded_uri;
        private string? loaded_entry;
        private Gst.State requested = Gst.State.NULL;
        private double resume_position;
        public bool stop_after_current { get; set; default = false; }
        public double saved_position { get { return resume_position > 0 ? resume_position : position (); } }
        public void restore_position (double seconds) { resume_position = double.max (0, seconds); }
        public void activate (int index) {
            if (!queue.select (index)) return;
            stop ();
            play ();
        }
        private void removed_current () {
            var before = requested;
            stop ();
            if (queue.current == null || before == Gst.State.NULL) return;
            play ();
            if (before == Gst.State.PAUSED) pause ();
        }
        private double level = 0.7;
        private AudioTap audio_tap;
        public unowned AudioTap visualization { get { return audio_tap; } }

        public Player (PlayQueue queue, Gst.Element? sink = null) {
            Object (queue: queue);
            queue.current_removed.connect (removed_current);
            pipeline = Gst.ElementFactory.make ("playbin", "player");
            audio_tap = new AudioTap ();
            if (pipeline == null) return;
            if (visualization.filter != null) pipeline.set ("audio-filter", visualization.filter);
            if (sink != null) pipeline.set ("audio-sink", sink);
            // Audio library: never create a video output window.
            var video_sink = Gst.ElementFactory.make ("fakesink", null);
            pipeline.set ("video-sink", video_sink, "volume", level);
            watch = pipeline.get_bus ().add_watch (Priority.DEFAULT, (bus, message) => {
                switch (message.type) {
                case Gst.MessageType.EOS:
                    bool stop_here = stop_after_current;
                    stop ();
                    if (!stop_here && queue.next ()) play ();
                    else finished ();
                    break;
                case Gst.MessageType.ERROR:
                    Error err;
                    string debug;
                    message.parse_error (out err, out debug);
                    stop ();
                    failure (err.message);
                    break;
                case Gst.MessageType.ASYNC_DONE:
                    if (resume_position > 0) {
                        double length = duration ();
                        double target = length > 0 ? double.min (resume_position, double.max (0, length - 0.05)) : resume_position;
                        if (!seek (target)) {
                            stop ();
                            failure ("No se pudo recuperar la posición guardada. Volvé a reproducir para empezar desde el inicio.");
                        } else {
                            resume_position = 0;
                            if (requested == Gst.State.PLAYING) pipeline.set_state (Gst.State.PLAYING);
                        }
                    }
                    break;
                case Gst.MessageType.STATE_CHANGED:
                    if (message.src == pipeline) {
                        Gst.State old_state, new_state, pending;
                        message.parse_state_changed (out old_state, out new_state, out pending);
                        state = new_state;
                        changed ();
                    }
                    break;
                default: break;
                }
                return Source.CONTINUE;
            });
        }
        public void play () {
            if (queue.current == null) return;
            if (pipeline == null) { failure ("No está disponible el plugin playbin de GStreamer."); return; }
            string uri = playable_uri (queue.current.uri);
            if (loaded_entry != null && loaded_entry != queue.current_entry.id) {
                stop_after_current = false;
                resume_position = 0;
            }
            if (loaded_uri != uri || loaded_entry != queue.current_entry.id || state == Gst.State.NULL) {
                pipeline.set_state (Gst.State.NULL);
                pipeline.set ("uri", uri);
                loaded_uri = uri;
                loaded_entry = queue.current_entry.id;
            }
            requested = Gst.State.PLAYING;
            if (pipeline.set_state (resume_position > 0 ? Gst.State.PAUSED : Gst.State.PLAYING) == Gst.StateChangeReturn.FAILURE) {
                stop ();
                failure ("No se pudo iniciar la reproducción; comprobá el archivo y los plugins.");
            }
            changed ();
        }
        public void pause () {
            requested = Gst.State.PAUSED;
            if (pipeline != null) pipeline.set_state (Gst.State.PAUSED);
        }
        public void stop () {
            requested = Gst.State.NULL;
            stop_after_current = false;
            resume_position = 0;
            if (pipeline != null) pipeline.set_state (Gst.State.NULL);
            loaded_uri = null;
            loaded_entry = null;
            state = Gst.State.NULL;
            changed ();
        }
        public void next () { if (queue.next ()) { stop (); play (); } }
        public void previous () { if (queue.previous ()) { stop (); play (); } }
        public void shutdown () {
            stop ();
            queue.current_removed.disconnect (removed_current);
            if (watch != 0) { Source.remove (watch); watch = 0; }
        }
        public bool seek (double seconds) {
            return pipeline != null && seconds >= 0 && pipeline.seek_simple (Gst.Format.TIME,
                Gst.SeekFlags.FLUSH | Gst.SeekFlags.KEY_UNIT, (int64) (seconds * Gst.SECOND));
        }
        public double position () {
            int64 value = 0;
            return pipeline != null && pipeline.query_position (Gst.Format.TIME, out value) ? (double) value / Gst.SECOND : 0;
        }
        public double duration () {
            int64 value = 0;
            return pipeline != null && pipeline.query_duration (Gst.Format.TIME, out value) ? (double) value / Gst.SECOND : 0;
        }
        public double volume {
            get { return level; }
            set { level = value.clamp (0, 1); if (pipeline != null) pipeline.set ("volume", level); }
        }
    }
}
