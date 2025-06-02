"""
Audio Analysis Tool - by Samuel Shipp with debug support from Claude 3.7 Sonnet by Anthropic -
particularly regarding PyInstaller setup, and command line arguments / flags.
See chat here: https://claude.ai/share/a5c27611-6d2d-446b-bccd-a8cad23f75f9
This script analyses audio files and outputs data in a text file for use in a Godot game.
It handles PyInstaller so the script can be exported as an executable.
The primary 'analyse_file' and 'main' functions are at the bottom of the script.
"""

import os
import sys
import numpy as np
import tkinter as tk
from tkinter import filedialog, messagebox
import shutil
import scipy
from scipy.io import wavfile
import librosa
import soundfile as sf
import torch

# Filter out PyInstaller arguments if running as executable
if getattr(sys, "frozen", False):
    # Save the original arguments
    original_args = sys.argv.copy()
    
    # Clear sys.argv and only add the script name back
    sys.argv = [sys.argv[0]]
    
    # Add back only arguments that aren't PyInstaller internal flags
    for arg in original_args[1:]:
        if not arg.startswith('-') or os.path.exists(arg):
            sys.argv.append(arg)
    
    print(f"Filtered arguments: {sys.argv}")

# Determine the application directory using the script's directory
def get_base_dir():
    """
    Get the base directory for the application, with special handling for PyInstaller
    """
    if getattr(sys, "frozen", False):
        # When running as a bundled executable
        base_path = os.path.dirname(sys.executable)
        # Create a permanent directory for data storage
        app_data_dir = os.path.join(os.path.expanduser("~"), "AudioAnalysisData")
        os.makedirs(app_data_dir, exist_ok=True)
        return app_data_dir
    else:
        # Running as a normal Python script
        if os.getcwd().endswith("scripts"):
            return os.getcwd()
        return os.path.dirname(os.path.abspath(__file__))


# Set up directories relative to the application
BASE_DIR = get_base_dir()
UPLOADED_AUDIO_DIR = os.path.join(BASE_DIR, "uploaded_audio")
ANALYSIS_RESULTS_DIR = os.path.join(BASE_DIR, "analysis_results")
SEPARATED_DIR = os.path.join(BASE_DIR, "htdemucs")

# Create necessary directories
os.makedirs(UPLOADED_AUDIO_DIR, exist_ok=True)
os.makedirs(ANALYSIS_RESULTS_DIR, exist_ok=True)
os.makedirs(SEPARATED_DIR, exist_ok=True)

# Debug - print the directories
print(f"Base directory: {BASE_DIR}")
print(f"Upload dir: {UPLOADED_AUDIO_DIR}")
print(f"Results dir: {ANALYSIS_RESULTS_DIR}")
print(f"Separated dir: {SEPARATED_DIR}")

# Global variables for uploaded files
uploaded_file_path = None
uploaded_file_name = None
original_file_extension = None

def convert_mp3_to_wav(mp3_path):
    """
    Convert MP3 file to WAV format
    """
    wav_path = os.path.splitext(mp3_path)[0] + ".wav"
    
    try:
        # Use librosa to read the mp3 file
        y, sr = librosa.load(mp3_path, sr=None)
        
        # Use soundfile to write the WAV file
        sf.write(wav_path, y, sr, format='WAV')
        
        return wav_path
    except Exception as e:
        print(f"Failed to convert MP3 to WAV: {e}")
        return None

def upload_audio(file_path=None):
    """
    Upload and process audio file, open a file dialog box
    """
    global uploaded_file_path
    global uploaded_file_name
    global original_file_extension
    
    if not file_path:
        # GUI mode, open file dialog
        root = tk.Tk()
        root.withdraw()  # Hide the main Tkinter window
        
        file_path = filedialog.askopenfilename(
            title="Select an audio file",
            filetypes=[("Audio files", ("*.wav", "*.mp3")),
                      ("WAV files", "*.wav"),
                      ("MP3 files", "*.mp3")]
        )
    
    if not file_path:
        print("No file selected")
        return False
    
    # Debugging - print the file path
    print(f"Processing file: {file_path}")
    
    # Validate the file exists
    if not os.path.isfile(file_path):
        print(f"Error: File does not exist: {file_path}")
        return False
    
    # Check if file is WAV or MP3
    file_extension = os.path.splitext(os.path.basename(file_path))[1].lower()
    print(f"Detected file extension: {file_extension}")
    
    if file_extension not in ['.wav', '.mp3']:
        print("Invalid file format. Only WAV and MP3 files are allowed!")
        if getattr(sys, "frozen", False):
            messagebox.showerror("Error", "Invalid file format. Only WAV and MP3 files are allowed!")
        return False
    
    # Store file name in all required formats
    original_file_extension = file_extension
    file_name = os.path.basename(file_path)
    uploaded_file_name = file_name
    destination_path = os.path.join(UPLOADED_AUDIO_DIR, file_name)
    
    try:
        # Copy the file to our directory
        shutil.copy(file_path, destination_path)
        print(f"File copied to: {destination_path}")
        
        # If it's an MP3, convert it to WAV
        if file_extension == '.mp3':
            wav_path = convert_mp3_to_wav(destination_path)
            if wav_path:
                uploaded_file_path = wav_path  # Use the converted WAV file
                if not getattr(sys, "frozen", False):  # Only show messagebox in non-frozen mode
                    messagebox.showinfo("ANALYSING", "Click OK and please wait a few moments.")
                print("MP3 converted to WAV successfully")
            else:
                return False  # Conversion failed
        else:
            uploaded_file_path = destination_path  # Use the WAV file directly
            if not getattr(sys, "frozen", False):  # Only show messagebox in non-frozen mode
                messagebox.showinfo("ANALYSING", "Click OK to begin analysis. It will take a minute or so to complete.")
            print("Using WAV file directly")
        
    except Exception as e:
        print(f"Failed to upload file: {e}")
        if getattr(sys, "frozen", False):
            messagebox.showerror("Error", f"Failed to process file: {e}")
        return False

    return True

def normalize_audio(y: np.ndarray) -> np.ndarray:
    """
    Peak‑normalize an audio signal
    """
    peak = np.max(np.abs(y))
    return y / peak if peak > 0 else y

def dominant_frequency(y: np.ndarray, fs: int) -> float:
    """
    Compute the frequency with the highest amplitude in the spectrum
    """
    spec = np.abs(np.fft.rfft(y))
    freq = np.fft.rfftfreq(len(y), d=1/fs)
    peak_index = np.argmax(spec)
    dominant_freq = freq[peak_index]
    return dominant_freq

def analyze_frequencies_based_on_beats(audio_path, tempo):
    """
    Analyze frequencies of an audio file based on beat locations
    """
    print(f"Analyzing frequencies for: {audio_path}")
    
    # Check if file exists
    if not os.path.exists(audio_path):
        print(f"Error: Audio file not found at {audio_path}")
        return []
    
    # Load audio using librosa for beat detection
    try:
        y, sr = librosa.load(audio_path, sr=None)
        y = normalize_audio(y)
        
        # Calculate beat times
        tempo2, beat_times = librosa.beat.beat_track(y=y, sr=sr, units='time')
        
        # Load the same audio with scipy for guaranteed compatbility with rest of function
        rate, data = scipy.io.wavfile.read(audio_path)
        
        # Convert stereo to mono if necessary
        if data.ndim > 1:
            data = data.mean(axis=1).astype(data.dtype)
        
        # Calculate frequencies at each beat position
        mean_frequencies = []
        
        for i in range(len(beat_times) - 1):
            # Convert beat times to sample indices
            start_sample = int(beat_times[i] * rate)
            end_sample = int(beat_times[i+1] * rate)
            
            # Extract the audio segment for this beat
            chunk = data[start_sample:end_sample]
            
            # Calculate mean frequency
            mean_freq = dominant_frequency(chunk, rate)
            mean_frequencies.append(mean_freq)
        
        return mean_frequencies
    except Exception as e:
        print(f"Error analyzing frequencies: {e}")
        return []

def analyze_energy_at_beats(audio_path):
    """
    Calculate energy levels of an audio file at each beat position
    """
    print(f"Analyzing energy for: {audio_path}")
    
    # Check if file exists
    if not os.path.exists(audio_path):
        print(f"Error: Audio file not found at {audio_path}")
        return []
    
    try:
        # Load audio using librosa
        y, sr = librosa.load(audio_path, sr=None)
        y = normalize_audio(y)
        
        # Get beat times
        _, beat_times = librosa.beat.beat_track(y=y, sr=sr, units='time')
        
        # Calculate RMS energy for the audio
        energy = librosa.feature.rms(y=y)[0]
        
        # Convert beat times to frames
        beat_frames = librosa.time_to_frames(beat_times, sr=sr)
        
        # Get energy at each beat point (ensure indices are within bounds)
        energy_at_beats = []
        for frame in beat_frames:
            if 0 <= frame < len(energy):
                energy_at_beats.append(float(energy[frame]))
            else:
                # Use the last available energy value if the frame is out of bounds
                energy_at_beats.append(float(energy[-1]) if len(energy) > 0 else 0.0)
        
        return energy_at_beats
    except Exception as e:
        print(f"Error analyzing energy: {e}")
        return []

def write_data_to_file(tempo, onset_times, cleaned_numbers, energy_vocals, energy_drums):
    """
    Write analysis results to a text file
    """
    # Generate output filename based on the input filename
    output_filename = os.path.splitext(uploaded_file_name)[0] + "_analysis.txt"
    output_path = os.path.join(ANALYSIS_RESULTS_DIR, output_filename)
    
    print(f"Writing analysis to: {output_path}")
    
    # Format the data in the desired structure
    with open(output_path, 'w') as f:
        f.write(f"uploaded_file_name: {uploaded_file_name}\n")
        f.write(f"tempo: {tempo}\n")
        
        # Format onset_times as a single line
        onset_str = str(onset_times).replace(", ", ", ")
        f.write(f"onset_times: {onset_str}\n")
        
        # Format mean_frequenciesV as a single line
        freq_str = str(cleaned_numbers).replace(", ", ", ")
        f.write(f"mean_frequenciesV: {freq_str}\n")
        
        # Format energy_vocals as a single line
        energy_vocals_str = str(energy_vocals).replace(", ", ", ")
        f.write(f"energy_vocals: {energy_vocals_str}\n")
        
        # Format energy_drums as a single line
        energy_drums_str = str(energy_drums).replace(", ", ", ")
        f.write(f"energy_drums: {energy_drums_str}\n")
    
    return output_path

def source_separation(file_path):
    """Separate audio sources using demucs"""
    try:
        print(f"Starting source separation for: {file_path}")
        
        # Check if file exists
        if not os.path.exists(file_path):
            print(f"Error: Audio file not found at {file_path}")
            return file_path, file_path
            
        import demucs.separate
        
        # Determine the correct folder path based on the file name without extension
        base_filename = os.path.splitext(os.path.basename(file_path))[0]
        folder_name = base_filename
        
        output_dir = os.path.dirname(SEPARATED_DIR)  # Go up two levels to get BASE_DIR/separated
        
        # The -o flag specifies the output directory
        demucs.separate.main(["-o", output_dir, "-n", "htdemucs", file_path])
        
        # Now the files will be in BASE_DIR/separated/htdemucs/folder_name/
        # Construct the full paths to the separated files
        vocals_path = os.path.join(SEPARATED_DIR, folder_name, "vocals.wav")
        drums_path = os.path.join(SEPARATED_DIR, folder_name, "drums.wav")
        
        print(f"Source separation complete. Vocals: {vocals_path}, Drums: {drums_path}")
        
        return vocals_path, drums_path
    except ImportError:
        print("WARNING: Demucs not available. Using original file for both vocals and drums.")
        return file_path, file_path
    except Exception as e:
        print(f"Error in source separation: {e}")
        return file_path, file_path

def analyze_file(file_path=None):
    """
    Main analysis function that can be called from Godot
    """
    # Step 1: Upload and process the audio file
    success = upload_audio(file_path)
    if not success:
        print("Failed to process audio file")
        return None
    
    print(f"Starting analysis for: {uploaded_file_path}")
    
    # Step 2: BPM Detection, generally uses Librosa due to intermittent issues with deeprhythm
    try:
        from deeprhythm import DeepRhythmPredictor
        model = DeepRhythmPredictor()
        audio, sr = librosa.load(uploaded_file_path)
        tempo = model.predict_from_audio(audio, sr)
        print(f"Detected tempo: {tempo} BPM")
    except ImportError:
        print("WARNING: DeepRhythm not available. Using librosa for tempo detection.")
        audio, sr = librosa.load(uploaded_file_path)
        tempo = librosa.beat.tempo(y=audio, sr=sr)[0]
        print(f"Detected tempo (librosa): {tempo} BPM")
    
    # Step 3: Source separation
    vocals_path, drums_path = source_separation(uploaded_file_path)

    # Step 4: Onset detection
    audio, sr = librosa.load(drums_path)
    onset_envelope = librosa.onset.onset_strength(y=audio, sr=sr)
    onset_frames = librosa.onset.onset_detect(
        onset_envelope=onset_envelope,
        sr=sr,
        units='time',
        pre_max=1,
        post_max=1,
        pre_avg=1,
        post_avg=1,
        delta=0.08,
        wait=1
    )
    onset_times = onset_frames.tolist()
    print(f"Detected {len(onset_times)} onsets")
    
    # Step 5: Frequency analysis on vocals
    mean_frequenciesV = analyze_frequencies_based_on_beats(vocals_path, tempo)
    cleaned_numbers = [float(num) for num in mean_frequenciesV]
    print(f"Analyzed {len(cleaned_numbers)} frequency segments")
    
    # Step 6: Calculate energy levels for vocals and drums
    energy_vocals = analyze_energy_at_beats(vocals_path)
    energy_drums = analyze_energy_at_beats(drums_path)
    print(f"Analyzed {len(energy_vocals)} vocal energy points and {len(energy_drums)} drum energy points")
    
    # Step 7: Write results to file
    output_path = write_data_to_file(tempo, onset_times, cleaned_numbers, energy_vocals, energy_drums)
    
    print(f"Analysis complete. Results saved to: {output_path}")
    return output_path

def main():
    """
    Main function when run as a standalone executable
    """
    print("\n=== AUDIO ANALYSIS START ===")
    
    # When running as a standalone executable
    if getattr(sys, "frozen", False):
        # Show a message to select a file
        root = tk.Tk()
        root.withdraw()
        messagebox.showinfo("Audio Analysis Tool", "Please select an audio file to analyze (WAV or MP3)")
        
    result = analyze_file()
    if result:
        if getattr(sys, "frozen", False):
            # Show a completion message with the result path
            messagebox.showinfo("Analysis Complete", f"Analysis completed successfully.\nResults saved to:\n{result}")
        print(f"Analysis completed successfully. Results at: {result}")
    else:
        if getattr(sys, "frozen", False):
            messagebox.showerror("Analysis Failed", "Could not complete the audio analysis.")
        print("Analysis failed.")

if __name__ == "__main__":
    """
    Command-line interface for both direct use and Godot integration
    """
    # Print all arguments for debugging
    print(f"Command line arguments: {sys.argv}")
    
    # If arguments are provided, check that they're valid file paths and not PyInstaller flags
    valid_file_arg = None
    
    if len(sys.argv) > 1:
        for arg in sys.argv[1:]:  # Skip the first argument (which is the script name)
            # Skip arguments that start with '-'
            if arg.startswith('-'):
                print(f"Skipping flag: {arg}")
                continue
                
            # Check if the argument is a valid file
            if os.path.isfile(arg):
                print(f"Found valid file argument: {arg}")
                valid_file_arg = arg
                break
    
    if valid_file_arg:
        result = analyze_file(valid_file_arg)
        if result:
            # Print just the path to the output file for Godot to capture
            print(result)
        sys.exit(0 if result else 1)
    else:
        # If no valid file arguments, run in GUI mode
        print("No valid file argument found, running in GUI mode.")
        main()
