namespace Music {
    [Compact]
    [CCode (cname = "MusicAudioTap", cheader_filename = "audio-tap.h", free_function = "music_audio_tap_free")]
    public class AudioTap {
        [CCode (cname = "music_audio_tap_new")]
        public AudioTap ();
        public unowned Gst.Element? filter { [CCode (cname = "music_audio_tap_get_filter")] get; }
        public bool available { [CCode (cname = "music_audio_tap_get_available")] get; }
        [CCode (cname = "music_audio_tap_enable")]
        public void enable (bool enabled);
        [CCode (cname = "music_audio_tap_read")]
        public uint8[] read ();
    }
}
