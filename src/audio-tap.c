#include "audio-tap.h"
#include <gst/audio/audio.h>
#include <string.h>

struct MusicAudioTap {
    gint refs;
    gint enabled;
    gint reset;
    GstElement *filter;
    gulong handler;
    GMutex mutex;
    guint8 pcm[8192];
    gint length;
    GstAudioInfo input;
    GstAudioConverter *converter;
};

static void unref_tap (MusicAudioTap *self) {
    if (!g_atomic_int_dec_and_test (&self->refs)) return;
    if (self->converter) gst_audio_converter_free (self->converter);
    g_mutex_clear (&self->mutex);
    g_free (self);
}

static void release_closure (gpointer data, GClosure *closure) { unref_tap (data); }

static void handoff (GstElement *identity, GstBuffer *buffer, MusicAudioTap *self) {
    if (!g_atomic_int_get (&self->enabled)) return;
    GstPad *pad = gst_element_get_static_pad (identity, "sink");
    GstCaps *caps = gst_pad_get_current_caps (pad);
    gst_object_unref (pad);
    GstAudioInfo info;
    gboolean valid = caps && gst_audio_info_from_caps (&info, caps);
    if (caps) gst_caps_unref (caps);
    if (!valid) return;
    if (!self->converter || !gst_audio_info_is_equal (&info, &self->input)) {
        if (self->converter) gst_audio_converter_free (self->converter);
        self->input = info;
        GstAudioInfo output;
        gst_audio_info_set_format (&output, GST_AUDIO_FORMAT_F32LE, 44100, 2, NULL);
        self->converter = gst_audio_converter_new (GST_AUDIO_CONVERTER_FLAG_NONE, &info, &output, NULL);
        if (!self->converter) return;
    }
    if (GST_BUFFER_FLAG_IS_SET (buffer, GST_BUFFER_FLAG_DISCONT) ||
        g_atomic_int_compare_and_exchange (&self->reset, 1, 0))
        gst_audio_converter_reset (self->converter);
    GstAudioBuffer audio;
    if (!gst_audio_buffer_map (&audio, &info, buffer, GST_MAP_READ)) return;
    gsize frames = gst_audio_converter_get_out_frames (self->converter, audio.n_samples);
    if (frames == 0) { gst_audio_buffer_unmap (&audio); return; }
    guint8 *converted = g_malloc (frames * 8);
    gpointer output[] = { converted };
    if (gst_audio_converter_samples (self->converter, GST_AUDIO_CONVERTER_FLAG_NONE,
            audio.planes, audio.n_samples, output, frames)) {
        gint length = MIN (frames * 8, sizeof (self->pcm));
        g_mutex_lock (&self->mutex);
        if (g_atomic_int_get (&self->enabled)) {
            memcpy (self->pcm, converted + frames * 8 - length, length);
            self->length = length;
        }
        g_mutex_unlock (&self->mutex);
    }
    g_free (converted);
    gst_audio_buffer_unmap (&audio);
}

MusicAudioTap *music_audio_tap_new (void) {
    MusicAudioTap *self = g_new0 (MusicAudioTap, 1);
    self->refs = 1;
    g_mutex_init (&self->mutex);
    gst_audio_info_init (&self->input);
    self->filter = gst_element_factory_make ("identity", NULL);
    if (self->filter) {
        gst_object_ref_sink (self->filter);
        // The signal owns a reference until pending handoffs have finished.
        g_atomic_int_inc (&self->refs);
        self->handler = g_signal_connect_data (self->filter, "handoff", G_CALLBACK (handoff),
            self, release_closure, 0);
    }
    return self;
}

void music_audio_tap_free (MusicAudioTap *self) {
    if (!self) return;
    music_audio_tap_enable (self, FALSE);
    if (self->filter) {
        g_signal_handler_disconnect (self->filter, self->handler);
        gst_object_unref (self->filter);
    }
    unref_tap (self);
}

GstElement *music_audio_tap_get_filter (MusicAudioTap *self) { return self->filter; }
gboolean music_audio_tap_get_available (MusicAudioTap *self) { return self->filter != NULL; }

void music_audio_tap_enable (MusicAudioTap *self, gboolean enabled) {
    g_mutex_lock (&self->mutex);
    g_atomic_int_set (&self->enabled, enabled);
    if (enabled) g_atomic_int_set (&self->reset, 1);
    self->length = 0;
    g_mutex_unlock (&self->mutex);
}

guint8 *music_audio_tap_read (MusicAudioTap *self, gint *length) {
    g_mutex_lock (&self->mutex);
    *length = self->length;
    guint8 *result = g_memdup2 (self->pcm, self->length);
    self->length = 0;
    g_mutex_unlock (&self->mutex);
    return result;
}
