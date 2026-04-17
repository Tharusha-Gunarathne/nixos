from gi.repository import Nautilus, GObject
import subprocess
import json
import os
import hashlib

VIDEO_EXTENSIONS = (".mp4", ".mkv", ".avi", ".mov", ".webm", ".flv")

CACHE_DIR = os.path.expanduser("~/.cache/nautilus-video-metadata")
os.makedirs(CACHE_DIR, exist_ok=True)


def cache_path(file_path):
    h = hashlib.md5(file_path.encode()).hexdigest()
    return os.path.join(CACHE_DIR, h + ".json")


def get_quality(height):
    if height >= 2160:
        return "4K"
    elif height >= 1440:
        return "1440p"
    elif height >= 1080:
        return "1080p"
    elif height >= 720:
        return "720p"
    return ""


def get_video_metadata(path):

    cache_file = cache_path(path)

    if os.path.exists(cache_file):
        try:
            with open(cache_file) as f:
                return json.load(f)
        except:
            pass

    try:
        result = subprocess.run(
            [
                "ffprobe",
                "-v", "quiet",
                "-print_format", "json",
                "-show_streams",
                "-show_format",
                path
            ],
            capture_output=True,
            text=True
        )

        data = json.loads(result.stdout)

        video = None
        audio = None

        for s in data.get("streams", []):
            if s.get("codec_type") == "video" and not video:
                video = s
            if s.get("codec_type") == "audio" and not audio:
                audio = s

        if not video:
            return None

        width = video.get("width")
        height = video.get("height")

        resolution = f"{width}x{height}" if width else ""

        quality = get_quality(height or 0)

        fps = video.get("r_frame_rate", "0/1")
        try:
            n, d = fps.split("/")
            fps = round(float(n) / float(d), 2)
        except:
            fps = ""

        codec = video.get("codec_name", "")

        duration = float(data.get("format", {}).get("duration", 0))
        hours = int(duration // 3600)
        minutes = int((duration % 3600) // 60)
        seconds = int(duration % 60)

        if hours:
            duration_str = f"{hours}:{minutes:02d}:{seconds:02d}"
        else:
            duration_str = f"{minutes}:{seconds:02d}"

        bitrate = data.get("format", {}).get("bit_rate")
        if bitrate:
            bitrate = f"{round(int(bitrate)/1000000,1)} Mbps"
        else:
            bitrate = ""

        audio_codec = ""
        audio_channels = ""

        if audio:
            audio_codec = audio.get("codec_name", "")
            audio_channels = str(audio.get("channels", ""))

        hdr = "HDR" if video.get("color_transfer") == "smpte2084" else "SDR"

        meta = {
            "duration": duration_str,
            "resolution": resolution,
            "quality": quality,
            "fps": str(fps),
            "codec": codec,
            "bitrate": bitrate,
            "audio_codec": audio_codec,
            "audio_channels": audio_channels,
            "hdr": hdr
        }

        with open(cache_file, "w") as f:
            json.dump(meta, f)

        return meta

    except:
        return None


class VideoMetadataColumns(GObject.GObject, Nautilus.ColumnProvider, Nautilus.InfoProvider):

    def get_columns(self):

        return [

            Nautilus.Column(
                name="NautilusPython::video_duration",
                attribute="video_duration",
                label="Duration",
                description="Video Duration"
            ),

            Nautilus.Column(
                name="NautilusPython::video_resolution",
                attribute="video_resolution",
                label="Resolution",
                description="Video Resolution"
            ),

            Nautilus.Column(
                name="NautilusPython::video_quality",
                attribute="video_quality",
                label="Quality",
                description="Video Quality"
            ),

            Nautilus.Column(
                name="NautilusPython::video_fps",
                attribute="video_fps",
                label="FPS",
                description="Frames per second"
            ),

            Nautilus.Column(
                name="NautilusPython::video_codec",
                attribute="video_codec",
                label="VCodec",
                description="Video Codec"
            ),

            Nautilus.Column(
                name="NautilusPython::video_bitrate",
                attribute="video_bitrate",
                label="Bitrate",
                description="Video Bitrate"
            ),

            Nautilus.Column(
                name="NautilusPython::audio_codec",
                attribute="audio_codec",
                label="ACodec",
                description="Audio Codec"
            ),

            Nautilus.Column(
                name="NautilusPython::audio_channels",
                attribute="audio_channels",
                label="Channels",
                description="Audio Channels"
            ),

            Nautilus.Column(
                name="NautilusPython::video_hdr",
                attribute="video_hdr",
                label="HDR",
                description="HDR / SDR"
            ),
        ]


    def update_file_info(self, file):

        path = file.get_location().get_path()

        if not path or not path.lower().endswith(VIDEO_EXTENSIONS):
            return

        meta = get_video_metadata(path)

        if not meta:
            return

        file.add_string_attribute("video_duration", meta["duration"])
        file.add_string_attribute("video_resolution", meta["resolution"])
        file.add_string_attribute("video_quality", meta["quality"])
        file.add_string_attribute("video_fps", meta["fps"])
        file.add_string_attribute("video_codec", meta["codec"])
        file.add_string_attribute("video_bitrate", meta["bitrate"])
        file.add_string_attribute("audio_codec", meta["audio_codec"])
        file.add_string_attribute("audio_channels", meta["audio_channels"])
        file.add_string_attribute("video_hdr", meta["hdr"])