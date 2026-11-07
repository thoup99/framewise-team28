--  Week 2 / P2 steps 2 and 3: read the raw sample tables of a MOV.
--
--  This is the stage between the box reader and Parse. It walks
--  moov/trak/mdia/minf/stbl, finds out what each track is, and copies the
--  tables out of the file exactly as they are stored. It does not work
--  out where any sample is: that is step 4 (resolve), which turns these
--  tables into the Track.Samples that Parse returns.
--
--  Why these types are not in Framewise.ISOBMFF: a Track holds finished
--  samples (offset, size, start), but the file stores something else.
--  stts and stsc are run-length, stsz can be a single number, and stco
--  counts chunks, not samples. Step 4 needs all of that side by side, and
--  clients of File_Map never need to see it, so it stays out of that spec.
--
--  AUDIO AND Max_Samples: one audio chunk will count as one sample.
--  PCM has one "sample" per audio tick: a 30 s mono proxy declares
--  1_440_009 of them, 22 times Max_Samples. Video and audio share one
--  Sample_Array type, so a bound that big would make every File_Map about
--  46 MB, just for that 30 s clip. Nothing needs it: a waveform draws from
--  chunk ranges, and ffmpeg groups that audio into 900 chunks. No detail is lost,
--  because PCM stsz gives one fixed size instead of a list, so a chunk's
--  byte size is its sample count times Uniform_Size. So for audio only, a
--  fixed-size stsz may declare any Sample_Count; it stores no entries, so
--  it uses no array space. Every stored table still has to fit.
--
--  No I/O and no heap allocation.

with Framewise.ISOBMFF.Boxes;

package Framewise.ISOBMFF.Tables with SPARK_Mode is

   --  One stts entry: "the next Sample_Count samples each last
   --  Sample_Delta ticks of the track's timescale".
   type Time_Run is record
      Sample_Count : Natural := 0;
      Sample_Delta : Natural := 0;
   end record;
   type Time_Run_Array is array (Sample_Index range 1 .. Max_Samples) of Time_Run;

   --  One stsc entry: "from chunk First_Chunk on, every chunk holds
   --  Samples_Per_Chunk samples", until the next entry takes over. The
   --  file's third field must be 1 and is not stored: we only accept
   --  files with one stsd entry, so there is nothing else it could say.
   type Chunk_Run is record
      First_Chunk       : Natural := 0;
      Samples_Per_Chunk : Natural := 0;
   end record;
   type Chunk_Run_Array is array (Sample_Index range 1 .. Max_Samples) of Chunk_Run;

   --  stsz sizes, or chunk file offsets (stco or co64).
   type Natural_Table is array (Sample_Index range 1 .. Max_Samples) of Natural
     with Default_Component_Value => 0;
   --  The default makes a Raw_Tables variable start fully initialized,
   --  like the other two arrays, whose records have defaults. SPARK
   --  insists on that before a variable is passed as "in out".

   --  A *_Count says how many entries are valid, like size() on a Java
   --  ArrayList. Array items past that count mean nothing.
   type Raw_Track is record
      Codec          : Track_Codec := None;  --  None: no such track in the file
      Entry_Type     : Boxes.Box_Kind := "    ";
      --  Kept as well as Codec: 'sowt' and 'twos' are both PCM_S16 but
      --  have opposite byte orders, which audio decoding will need.

      Timescale      : Natural := 0;
      --  From mdhd: how many stts ticks make one second. 0 when the track
      --  has no mdhd. Read_Tables does not reject 0; step 4 does, because
      --  that is where the timescale is divided by.

      Time_Run_Count : Sample_Index := 0;
      Time_Runs      : Time_Run_Array;

      Chunk_Run_Count : Sample_Index := 0;
      Chunk_Runs      : Chunk_Run_Array;

      Sample_Count   : Natural := 0;  --  samples stsz declares
      Uniform_Size   : Natural := 0;  --  /= 0: all samples have this size
      Size_Count     : Sample_Index := 0;  --  0 when Uniform_Size /= 0
      Sizes          : Natural_Table;

      Chunk_Count    : Sample_Index := 0;
      Chunk_Offsets  : Natural_Table;
   end record;

   type Raw_Tables is record
      Video : Raw_Track;
      Audio : Raw_Track;
   end record;
   --  About 3 MB. A local variable is fine in the main program, but a
   --  task gets a much smaller stack, and running out raises Storage_Error.

   procedure Read_Tables
     (Data      : Byte_Array;
      File_Size : Natural;
      Tables    : in out Raw_Tables;
      Ok        : out Boolean)
     with Post =>
       (if Ok then
          Tables.Video.Codec in None | JPEG
          and then Tables.Audio.Codec in None | PCM_S16
          and then (Tables.Video.Codec /= None or else Tables.Audio.Codec /= None));
   --  Data holds the file from its first byte through the end of moov, at
   --  the file's own positions. File_Size is the size of the whole file.
   --
   --  Ok = True: the moov is complete, and every track is one this
   --  package accepts. Tracks with a handler other than 'vide' or 'soun'
   --  are skipped. Every table entry that fits the bounds is stored.
   --
   --  Ok = False, with all counts 0 and Codec = None, for: a missing or
   --  truncated box; an mdhd too short for its version, or with a version
   --  other than 0 or 1; a table that does not fit Max_Samples; a table count
   --  that needs more bytes than its box has; a nonzero version or flags
   --  field in a table; an stsd with anything but one entry; an unknown
   --  codec; a second video or second audio track; or no video or audio
   --  track at all.
   --
   --  Tables is "in out" so that this procedure need not build a 3 MB
   --  value to overwrite it: it resets the counts and Codec instead. The
   --  entries are stored as they are, so comparing the tables with each
   --  other (do the stts counts add up to Sample_Count, are stsc runs in
   --  order) is left to step 4, which has to walk them anyway.

end Framewise.ISOBMFF.Tables;
