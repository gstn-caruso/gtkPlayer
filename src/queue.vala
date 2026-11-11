namespace Music {
    public class QueueEntry : Object {
        public string id { get; construct; }
        public Track track { get; construct; }
        public QueueEntry (Track track, string? id = null) {
            Object (track: track, id: id ?? Uuid.string_random ());
        }
    }

    public class PlayQueue : Object {
        public QueueEntry[] entries { get; private set; default = {}; }
        public Track[] tracks {
            owned get {
                Track[] result = {};
                foreach (var entry in entries) result += entry.track;
                return result;
            }
        }
        public int index { get; private set; default = -1; }
        public QueueEntry? current_entry { get { return index >= 0 && index < entries.length ? entries[index] : null; } }
        public Track? current { get { return current_entry == null ? null : current_entry.track; } }
        public bool can_undo { get { return removed != null; } }
        public uint revision { get; private set; }
        private QueueEntry[]? removed;
        public signal void changed ();
        public signal void current_removed ();

        private void edited () { removed = null; revision++; changed (); }
        public int find (string id) {
            for (int i = 0; i < entries.length; i++) if (entries[i].id == id) return i;
            return -1;
        }
        public void replace (Track[] tracks) {
            bool had_current = current != null;
            QueueEntry[] fresh = {};
            foreach (var track in tracks) fresh += new QueueEntry (track);
            entries = fresh;
            index = -1;
            edited ();
            if (had_current) current_removed ();
        }
        public void restore (QueueEntry[] entries, string? current_id) {
            this.entries = entries;
            index = current_id == null ? -1 : find (current_id);
            edited ();
        }
        public int insert (Track[] tracks, int position) {
            if (tracks.length == 0) return -1;
            position = position.clamp (0, entries.length);
            QueueEntry[] result = {};
            for (int i = 0; i < position; i++) result += entries[i];
            foreach (var track in tracks) result += new QueueEntry (track);
            for (int i = position; i < entries.length; i++) result += entries[i];
            entries = result;
            if (index >= position) index += tracks.length;
            edited ();
            return position;
        }
        public int append (Track[] tracks) { return insert (tracks, entries.length); }
        public int insert_next (Track[] tracks) { return insert (tracks, index + 1); }
        public bool move (int from, int to) {
            if (from < 0 || from >= entries.length || to < 0 || to >= entries.length || from == to) return false;
            var active = current_entry;
            var moving = entries[from];
            QueueEntry[] result = {};
            foreach (var entry in entries) if (entry != moving) result += entry;
            QueueEntry[] reordered = {};
            for (int i = 0; i <= result.length; i++) {
                if (i == to) reordered += moving;
                if (i < result.length) reordered += result[i];
            }
            entries = reordered;
            index = active == null ? -1 : find (active.id);
            edited ();
            return true;
        }
        public bool remove (int position) {
            if (position < 0 || position >= entries.length) return false;
            bool active = position == index;
            QueueEntry[] result = {};
            for (int i = 0; i < entries.length; i++) if (i != position) result += entries[i];
            entries = result;
            if (position < index) index--;
            else if (active && index >= entries.length) index = -1;
            edited ();
            if (active) current_removed ();
            return true;
        }
        public bool clear () {
            if (entries.length == (current_entry == null ? 0 : 1)) return false;
            var active = current_entry;
            removed = entries;
            QueueEntry[] kept = {};
            if (active != null) kept += active;
            entries = kept;
            index = active == null ? -1 : 0;
            revision++;
            changed ();
            return true;
        }
        public bool undo_clear () {
            if (removed == null) return false;
            var active = current_entry;
            entries = removed;
            removed = null;
            index = active == null ? -1 : find (active.id);
            revision++;
            changed ();
            return true;
        }
        public bool select (int index) {
            if (index < 0 || index >= entries.length) return false;
            this.index = index;
            changed ();
            return true;
        }
        public bool next () { return entries.length > 0 && select (index + 1); }
        public bool previous () { return select (index - 1); }
    }
}
