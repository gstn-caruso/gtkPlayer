#pragma once
#include <glib.h>

typedef struct MusicVisualizerRenderer MusicVisualizerRenderer;
MusicVisualizerRenderer *music_visualizer_renderer_new (void);
void music_visualizer_renderer_free (MusicVisualizerRenderer *self);
void music_visualizer_renderer_step (MusicVisualizerRenderer *self, int direction, gboolean smooth);
gboolean music_visualizer_renderer_render (MusicVisualizerRenderer *self,
    const guint8 *pcm, int pcm_length, int width, int height);
guint music_visualizer_renderer_get_preset (MusicVisualizerRenderer *self);
guint music_visualizer_renderer_get_switches (MusicVisualizerRenderer *self);
