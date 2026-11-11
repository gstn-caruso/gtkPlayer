namespace Music {
    [Compact]
    [CCode (cname = "MusicVisualizerRenderer", cheader_filename = "visualizer-renderer.h", free_function = "music_visualizer_renderer_free")]
    internal class VisualizerRenderer {
        [CCode (cname = "music_visualizer_renderer_new")]
        public VisualizerRenderer ();
        [CCode (cname = "music_visualizer_renderer_step")]
        public void step (int direction, bool smooth);
        [CCode (cname = "music_visualizer_renderer_render")]
        public bool render (uint8[] pcm, int width, int height);
        [CCode (cname = "music_visualizer_renderer_get_preset")]
        public uint get_preset ();
        [CCode (cname = "music_visualizer_renderer_get_switches")]
        public uint get_switches ();
    }
}
