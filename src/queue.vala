namespace Music {
    public class PlayQueue : Object {
        public Track[] tracks { get; private set; default = {}; }
        public int index { get; private set; default = -1; }
        public Track? current { get { return index >= 0 && index < tracks.length ? tracks[index] : null; } }
        public void replace (Track[] tracks) { this.tracks = tracks; index = -1; }
        public bool select (int index) {
            if (index < 0 || index >= tracks.length) return false;
            this.index = index;
            return true;
        }
        public bool next () { return select (index + 1); }
        public bool previous () { return select (index - 1); }
    }
}
