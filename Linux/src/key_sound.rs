use std::{
    fs::File,
    io::{self, Write},
    process::Command,
    time::{Duration, Instant},
};

use crate::models::support_directory;

pub struct KeySoundPlayer {
    last_played: Option<Instant>,
}

impl KeySoundPlayer {
    pub fn new() -> Self {
        Self { last_played: None }
    }

    pub fn play(&mut self) {
        if self
            .last_played
            .is_some_and(|last_played| last_played.elapsed() < Duration::from_millis(25))
        {
            return;
        }
        self.last_played = Some(Instant::now());

        let path = support_directory().join("soft-key.wav");
        if !path.exists() && write_soft_key(&path).is_err() {
            return;
        }
        if Command::new("paplay").arg(&path).spawn().is_err() {
            let _ = Command::new("aplay").arg(&path).spawn();
        }
    }
}

fn write_soft_key(path: &std::path::Path) -> io::Result<()> {
    std::fs::create_dir_all(support_directory())?;
    const SAMPLE_RATE: u32 = 44_100;
    const SAMPLE_COUNT: usize = (SAMPLE_RATE as f64 * 0.058) as usize;
    let mut samples = Vec::with_capacity(SAMPLE_COUNT);

    for index in 0..SAMPLE_COUNT {
        let time = index as f64 / SAMPLE_RATE as f64;
        let low_noise = (noise(index as i32)
            + noise(index as i32 - 1)
            + noise(index as i32 - 2)
            + noise(index as i32 - 3)
            + noise(index as i32 - 4))
            / 5.0;
        let cushion = low_noise * (-time / 0.018).exp() * 0.20;
        let warmth = (std::f64::consts::TAU * 235.0 * time).sin() * (-time / 0.024).exp() * 0.10;
        let sample = ((cushion + warmth) * 0.60).clamp(-1.0, 1.0);
        samples.push((sample * i16::MAX as f64) as i16);
    }

    let mut file = File::create(path)?;
    file.write_all(b"RIFF")?;
    file.write_all(&(36 + samples.len() as u32 * 2).to_le_bytes())?;
    file.write_all(b"WAVEfmt ")?;
    file.write_all(&16u32.to_le_bytes())?;
    file.write_all(&1u16.to_le_bytes())?;
    file.write_all(&1u16.to_le_bytes())?;
    file.write_all(&SAMPLE_RATE.to_le_bytes())?;
    file.write_all(&(SAMPLE_RATE * 2).to_le_bytes())?;
    file.write_all(&2u16.to_le_bytes())?;
    file.write_all(&16u16.to_le_bytes())?;
    file.write_all(b"data")?;
    file.write_all(&(samples.len() as u32 * 2).to_le_bytes())?;
    for sample in samples {
        file.write_all(&sample.to_le_bytes())?;
    }
    Ok(())
}

fn noise(index: i32) -> f64 {
    let mut value = index as i64 as u64 + 0x50F7;
    value = (value ^ (value >> 30)).wrapping_mul(0xBF58476D1CE4E5B9);
    value = (value ^ (value >> 27)).wrapping_mul(0x94D049BB133111EB);
    value ^= value >> 31;
    (value & 0xFFFF) as f64 / 32767.5 - 1.0
}
