using System.Media;
using System.Text;
using System.IO;

namespace Plaintext.Windows;

public sealed class KeySoundPlayer
{
    private DateTime lastPlayed = DateTime.MinValue;
    private readonly Lazy<SoundPlayer> player;

    public KeySoundPlayer()
    {
        player = new Lazy<SoundPlayer>(() =>
        {
            var path = Path.Combine(SettingsStore.SupportDirectory, "soft-key.wav");
            if (!File.Exists(path)) WriteSoftKey(path);
            return new SoundPlayer(path);
        });
    }

    public void Play()
    {
        if ((DateTime.UtcNow - lastPlayed).TotalMilliseconds < 25) return;
        lastPlayed = DateTime.UtcNow;
        try { player.Value.Play(); }
        catch { }
    }

    private static void WriteSoftKey(string path)
    {
        const int sampleRate = 44_100;
        const double duration = 0.058;
        var sampleCount = (int)(sampleRate * duration);
        var pcm = new short[sampleCount];

        for (var index = 0; index < sampleCount; index++)
        {
            var time = (double)index / sampleRate;
            var lowNoise = (Noise(index) + Noise(index - 1) + Noise(index - 2) + Noise(index - 3) + Noise(index - 4)) / 5d;
            var cushion = lowNoise * Math.Exp(-time / 0.018) * 0.20;
            var warmth = Math.Sin(2 * Math.PI * 235 * time) * Math.Exp(-time / 0.024) * 0.10;
            var sample = Math.Clamp((cushion + warmth) * 0.60, -1d, 1d);
            pcm[index] = (short)(sample * short.MaxValue);
        }

        using var writer = new BinaryWriter(File.Create(path), Encoding.ASCII);
        writer.Write(Encoding.ASCII.GetBytes("RIFF"));
        writer.Write(36 + pcm.Length * sizeof(short));
        writer.Write(Encoding.ASCII.GetBytes("WAVEfmt "));
        writer.Write(16);
        writer.Write((short)1);
        writer.Write((short)1);
        writer.Write(sampleRate);
        writer.Write(sampleRate * sizeof(short));
        writer.Write((short)sizeof(short));
        writer.Write((short)16);
        writer.Write(Encoding.ASCII.GetBytes("data"));
        writer.Write(pcm.Length * sizeof(short));
        foreach (var sample in pcm) writer.Write(sample);
    }

    private static double Noise(int index)
    {
        ulong value = unchecked((ulong)(long)index) + 0x50F7;
        value = (value ^ (value >> 30)) * 0xBF58476D1CE4E5B9;
        value = (value ^ (value >> 27)) * 0x94D049BB133111EB;
        value ^= value >> 31;
        return (value & 0xFFFF) / 32767.5 - 1;
    }
}
