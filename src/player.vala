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
        private double level = 0.7;

        public Player (PlayQueue queue, Gst.Element? sink = null) {
            Object (queue: queue);
            pipeline = Gst.ElementFactory.make ("playbin", "player");
            if (pipeline == null) return;
            if (sink != null) pipeline.set ("audio-sink", sink);
            // Audio library: never create a video output window.
            var video_sink = Gst.ElementFactory.make ("fakesink", null);
            pipeline.set ("video-sink", video_sink, "volume", level);
            watch = pipeline.get_bus ().add_watch (Priority.DEFAULT, (bus, message) => {
                switch (message.type) {
                case Gst.MessageType.EOS:
                    stop ();
                    if (queue.next ()) play ();
                    else finished ();
                    break;
                case Gst.MessageType.ERROR:
                    Error err;
                    string debug;
                    message.parse_error (out err, out debug);
                    stop ();
                    failure (err.message);
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
            if (loaded_uri != uri || state == Gst.State.NULL) {
                pipeline.set_state (Gst.State.NULL);
                pipeline.set ("uri", uri);
                loaded_uri = uri;
            }
            if (pipeline.set_state (Gst.State.PLAYING) == Gst.StateChangeReturn.FAILURE) {
                stop ();
                failure ("No se pudo iniciar la reproducción; comprobá el archivo y los plugins.");
            }
            changed ();
        }
        public void pause () {
            if (pipeline != null) pipeline.set_state (Gst.State.PAUSED);
        }
        public void stop () {
            if (pipeline != null) pipeline.set_state (Gst.State.NULL);
            loaded_uri = null;
            state = Gst.State.NULL;
            changed ();
        }
        public void next () { if (queue.next ()) { stop (); play (); } }
        public void previous () { if (queue.previous ()) { stop (); play (); } }
        public void shutdown () {
            stop ();
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
