#include "visualizer-renderer.h"
#include <projectM-4/projectM.h>
#include <epoxy/gl.h>
#include <gst/gst.h>
#include <string.h>

struct MusicVisualizerRenderer {
    projectm_handle engine;
    guint preset;
    guint switches;
    gboolean switch_pending;
    int pending_preset;
    gboolean pending_smooth;
    gboolean failed;
    int width;
    int height;
};

/* Original, self-contained MilkDrop equations: no external files, shaders or
 * textures. Vary geometry and colour; bass/mid/treb control motion and waves.
 * Loading paths, remote presets and editing are deliberately not exposed. */
static const char *presets[] = {
    "nWaveMode=0\nfWaveScale=1.5\nfDecay=0.96\n"
    "per_frame_1=wave_r=0.4+0.3*sin(time*0.4);wave_g=0.7;wave_b=0.9;\n"
    "per_frame_2=zoom=1.01+0.005*bass;rot=0.008*sin(time*0.3);wave_mystery=0.2*sin(time);\n",
    "nWaveMode=1\nfWaveScale=1.8\nfDecay=0.96\n"
    "per_frame_1=wave_r=0.9;wave_g=0.3+0.25*sin(time*0.3);wave_b=0.5;\n"
    "per_frame_2=zoom=1.01+0.004*mid;rot=0.01;cx=0.5+0.08*sin(time*0.4);\n",
    "nWaveMode=2\nfWaveScale=1.6\nfDecay=0.95\n"
    "per_frame_1=wave_r=0.3;wave_g=0.8;wave_b=0.4+0.3*sin(time*0.5);\n"
    "per_frame_2=zoom=1.015+0.004*bass;rot=0.006*sin(time);warp=0.2+0.1*mid;\n",
    "nWaveMode=5\nfWaveScale=1.4\nfDecay=0.95\n"
    "per_frame_1=wave_r=0.8;wave_g=0.6+0.2*sin(time*0.4);wave_b=0.3;\n"
    "per_frame_2=zoom=1.01;rot=0.008*sin(time*0.6);wave_x=0.5+0.1*sin(time*0.3);\n",
    "nWaveMode=6\nfWaveScale=1.6\nfDecay=0.96\n"
    "per_frame_1=wave_r=0.6+0.3*sin(time*0.4);wave_g=0.4;wave_b=0.9;\n"
    "per_frame_2=zoom=1.012+0.003*treb;rot=-0.006;wave_y=0.5+0.1*sin(time*0.5);\n"
};

static void request_switch (bool hard_cut, void *data) {
    /* Defer loading until render_frame returns; callbacks run inside projectM. */
    ((MusicVisualizerRenderer *) data)->switch_pending = TRUE;
}

static void preset_failed (const char *filename, const char *message, void *data) {
    ((MusicVisualizerRenderer *) data)->failed = TRUE;
    g_warning ("No se pudo cargar un efecto del visualizador: %s", message);
}

static void load_preset (MusicVisualizerRenderer *self, guint preset, gboolean smooth) {
    self->preset = preset;
    char *geometry = g_strdup_printf (
        "shapecode_0_enabled=1\nshapecode_0_sides=%u\nshapecode_0_additive=1\n"
        "shapecode_0_num_inst=3\nshapecode_0_a=0.03\nshapecode_0_a2=0.0\n"
        "shapecode_0_border_a=0.4\nshapecode_0_border_r=0.4\nshapecode_0_border_g=0.6\nshapecode_0_border_b=0.9\n"
        "shape_0_per_frame1=ang=time*0.1+instance*2.094;rad=0.25+0.06*bass;\n"
        "shape_0_per_frame2=x=0.5+0.12*cos(time*0.2+instance*2.094);y=0.5+0.12*sin(time*0.2+instance*2.094);\n"
        "shape_0_per_frame3=r=0.5+0.4*sin(time*0.13);g=0.5+0.4*sin(time*0.17+2);b=0.5+0.4*sin(time*0.11+4);\n",
        3 + self->preset * 2);
    char *data = g_strconcat ("[preset00]\nfRating=3.0\nfGammaAdj=1.0\n"
        "bWaveDots=0\nbAdditiveWaves=1\nbWaveThick=1\nfWaveAlpha=0.85\n",
        presets[self->preset], geometry, NULL);
    projectm_load_preset_data (self->engine, data, smooth);
    g_free (geometry);
    g_free (data);
    self->switch_pending = FALSE;
    self->switches++;
}

static void next_preset (MusicVisualizerRenderer *self, gboolean smooth) {
    guint count = G_N_ELEMENTS (presets);
    guint next = self->switches == 0 ? g_random_int_range (0, count) :
        (self->preset + g_random_int_range (1, count)) % count;
    load_preset (self, next, smooth);
}

void music_visualizer_renderer_step (MusicVisualizerRenderer *self, int direction, gboolean smooth) {
    int count = G_N_ELEMENTS (presets);
    int current = self->pending_preset >= 0 ? self->pending_preset : (int) self->preset;
    self->pending_preset = (current + (direction < 0 ? count - 1 : 1)) % count;
    self->pending_smooth = smooth;
}

MusicVisualizerRenderer *music_visualizer_renderer_new (void) {
    MusicVisualizerRenderer *self = g_new0 (MusicVisualizerRenderer, 1);
    self->pending_preset = -1;
    self->engine = projectm_create ();
    if (!self->engine) { g_free (self); return NULL; }
    projectm_set_preset_switch_requested_event_callback (self->engine, request_switch, self);
    projectm_set_preset_switch_failed_event_callback (self->engine, preset_failed, self);
    projectm_set_preset_duration (self->engine, 20.0);
    projectm_set_easter_egg (self->engine, 0.0);
    projectm_set_soft_cut_duration (self->engine, 3.0);
    // Beat-responsive motion, gentle transitions: avoid repeated flashing cuts.
    projectm_set_hard_cut_enabled (self->engine, false);
    projectm_set_mesh_size (self->engine, 48, 32);
    projectm_set_fps (self->engine, 30);
    projectm_set_aspect_correction (self->engine, true);
    next_preset (self, FALSE);
    return self;
}

void music_visualizer_renderer_free (MusicVisualizerRenderer *self) {
    if (!self) return;
    projectm_destroy (self->engine);
    g_free (self);
}

gboolean music_visualizer_renderer_render (MusicVisualizerRenderer *self,
    const guint8 *pcm, int pcm_length, int width, int height) {
    if (self->failed) return FALSE;
    GLint framebuffer;
    glGetIntegerv (GL_DRAW_FRAMEBUFFER_BINDING, &framebuffer);
    if (width != self->width || height != self->height) {
        projectm_set_window_size (self->engine, width, height);
        self->width = width;
        self->height = height;
    }
    // PCM is always interleaved F32LE stereo; copy for alignment and endian safety.
    float samples[2048];
    guint frames = MIN ((guint) pcm_length / 8, G_N_ELEMENTS (samples) / 2);
    for (guint i = 0; i < frames * 2; i++) {
        guint32 bits = GST_READ_UINT32_LE (pcm + pcm_length - frames * 8 + i * 4);
        memcpy (&samples[i], &bits, sizeof (float));
    }
    if (frames) projectm_pcm_add_float (self->engine, samples, frames, PROJECTM_STEREO);
    else {
        memset (samples, 0, sizeof (samples));
        projectm_pcm_add_float (self->engine, samples, 512, PROJECTM_STEREO);
    }
    if (self->pending_preset >= 0) {
        load_preset (self, self->pending_preset, self->pending_smooth);
        self->pending_preset = -1;
    } else if (self->switch_pending) next_preset (self, TRUE);
    // Resize/load can bind projectM's internal FBOs; restore GTK's draw target.
    glBindFramebuffer (GL_DRAW_FRAMEBUFFER, framebuffer);
    projectm_opengl_render_frame (self->engine);
    glBindFramebuffer (GL_FRAMEBUFFER, framebuffer);
    // GTK composites this texture. projectM's feedback alpha is not window alpha.
    glColorMask (GL_FALSE, GL_FALSE, GL_FALSE, GL_TRUE);
    glClearColor (0, 0, 0, 1);
    glClear (GL_COLOR_BUFFER_BIT);
    glColorMask (GL_TRUE, GL_TRUE, GL_TRUE, GL_TRUE);
    return !self->failed;
}

guint music_visualizer_renderer_get_preset (MusicVisualizerRenderer *self) { return self->preset; }
guint music_visualizer_renderer_get_switches (MusicVisualizerRenderer *self) { return self->switches; }
