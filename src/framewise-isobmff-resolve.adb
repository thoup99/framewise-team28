--  The loop invariants below are for GNATprove (P3), which proves them
--  whatever this says. Checking one at run time would re-test every
--  earlier sample on each pass, N * N / 2 checks for N samples, and the
--  "if not Inside then return" just before it already ensures the same.
pragma Assertion_Policy (Loop_Invariant => Ignore);

package body Framewise.ISOBMFF.Resolve with SPARK_Mode is

   use Framewise.ISOBMFF.Tables;

   --  How far the walk through stts has got. Run is the current stts
   --  entry, Left how many of its samples are not used yet, and Ticks the
   --  sum of every duration used so far, in the track's own timescale.
   type Clock is record
      Run   : Sample_Index := 0;
      Left  : Natural := 0;
      Ticks : Time := 0;
   end record;

   procedure Advance
     (Raw   : Raw_Track;
      C     : in out Clock;
      Count : Natural;
      Ok    : out Boolean);

   procedure To_Framewise
     (Ticks     : Time;
      Timescale : Positive;
      Result    : out Time;
      Ok        : out Boolean);

   procedure Resolve_Video
     (Raw        : Raw_Track;
      Mdat_First : Natural;
      Mdat_Last  : Natural;
      T          : in out Track;
      C          : in out Clock;
      Ok         : out Boolean)
     with Post => (if Ok then Track_OK (T, Mdat_First, Mdat_Last));

   procedure Resolve_Audio
     (Raw        : Raw_Track;
      Mdat_First : Natural;
      Mdat_Last  : Natural;
      T          : in out Track;
      C          : in out Clock;
      Ok         : out Boolean)
     with Post => (if Ok then Track_OK (T, Mdat_First, Mdat_Last));

   function Tables_Agree (Raw : Raw_Track) return Boolean is
      Total      : Natural := 0;  --  samples counted so far
      Run        : Chunk_Run;
      Next_First : Natural;       --  first chunk of the run after Run
      Chunks     : Natural;       --  how many chunks Run covers
   begin
      --  stts. Each count is compared with what is still missing before
      --  it is added, so Total stays <= Sample_Count and cannot overflow.
      for I in 1 .. Raw.Time_Run_Count loop
         if Raw.Time_Runs (I).Sample_Count > Raw.Sample_Count - Total then
            return False;
         end if;
         Total := Total + Raw.Time_Runs (I).Sample_Count;
      end loop;
      if Total /= Raw.Sample_Count then
         return False;
      end if;

      --  stsz. Read_Stsz already makes this true; checking it again here
      --  lets the walks below rely on it without knowing that.
      if Raw.Uniform_Size = 0 and then Natural (Raw.Size_Count) /= Raw.Sample_Count then
         return False;
      end if;

      --  stsc. Chunks with no run at all: nothing says what is in them.
      if Raw.Chunk_Count > 0 and then Raw.Chunk_Run_Count = 0 then
         return False;
      end if;

      Total := 0;
      for I in 1 .. Raw.Chunk_Run_Count loop
         Run := Raw.Chunk_Runs (I);
         if Run.Samples_Per_Chunk = 0
           or else Run.First_Chunk > Natural (Raw.Chunk_Count)
           or else (I = 1 and then Run.First_Chunk /= 1)
         then
            return False;
         end if;

         --  A run lasts until the next run starts. The last run lasts
         --  through the last chunk. This is the run-length trap.
         if I < Raw.Chunk_Run_Count then
            Next_First := Raw.Chunk_Runs (I + 1).First_Chunk;
         else
            Next_First := Natural (Raw.Chunk_Count) + 1;
         end if;

         --  The next run must start later, so runs are strictly in order.
         if Next_First <= Run.First_Chunk then
            return False;
         end if;

         --  Chunks * Samples_Per_Chunk more samples. Dividing first keeps
         --  this check from overflowing, like the stts one above.
         Chunks := Next_First - Run.First_Chunk;
         if Chunks > (Raw.Sample_Count - Total) / Run.Samples_Per_Chunk then
            return False;
         end if;
         Total := Total + Chunks * Run.Samples_Per_Chunk;
      end loop;

      return Total = Raw.Sample_Count;
   end Tables_Agree;

   --  Moves C forward by Count samples and adds their durations to Ticks.
   --  stts is run-length, so one call may finish a run and start the next.
   procedure Advance
     (Raw   : Raw_Track;
      C     : in out Clock;
      Count : Natural;
      Ok    : out Boolean)
   is
      Need : Natural := Count;  --  samples still to step over
      Take : Natural;           --  how many of them this run gives
      Step : Time;              --  duration of one sample in this run
   begin
      Ok := False;

      while Need > 0 loop
         if C.Left = 0 then
            --  This run is used up: go to the next. Tables_Agree makes
            --  sure there is one, but a missing one must not raise.
            if C.Run >= Raw.Time_Run_Count then
               return;
            end if;
            C.Run := C.Run + 1;
            C.Left := Raw.Time_Runs (C.Run).Sample_Count;
         else
            Take := Natural'Min (Need, C.Left);
            Step := Time (Raw.Time_Runs (C.Run).Sample_Delta);

            --  Ticks + Take * Step must fit Time. Asking it as a division
            --  means the check itself cannot overflow.
            if Step > 0 and then Time (Take) > (Time'Last - C.Ticks) / Step then
               return;
            end if;

            C.Ticks := C.Ticks + Time (Take) * Step;
            C.Left := C.Left - Take;
            Need := Need - Take;
         end if;
      end loop;

      Ok := True;
   end Advance;

   --  Ticks of the track's timescale to Framewise ticks:
   --  Ticks * Timebase / Timescale. Refused if Ticks * Timebase would
   --  not fit Time. Integer division rounds down; it is exact when
   --  Timescale divides Ticks * Timebase, as it does for the proxy.
   procedure To_Framewise
     (Ticks     : Time;
      Timescale : Positive;
      Result    : out Time;
      Ok        : out Boolean)
   is
   begin
      if Ticks > Time'Last / Timebase then
         Result := 0;
         Ok := False;
      else
         Result := Ticks * Timebase / Time (Timescale);
         Ok := True;
      end if;
   end To_Framewise;

   --  Video: one Sample per frame. The loop goes sample by sample and
   --  remembers which chunk it is in and where in that chunk.
   procedure Resolve_Video
     (Raw        : Raw_Track;
      Mdat_First : Natural;
      Mdat_Last  : Natural;
      T          : in out Track;
      C          : in out Clock;
      Ok         : out Boolean)
   is
      Count    : Sample_Index;
      Chunk    : Sample_Index := 0;  --  the chunk sample I is in
      Run      : Sample_Index := 0;  --  the stsc run that chunk is in
      Left     : Natural := 0;       --  samples of this chunk not placed yet
      Position : Natural := 0;       --  where the next sample of the chunk starts
      Size     : Natural;
      Start    : Time;
      Good     : Boolean;
   begin
      Ok := False;

      if Raw.Sample_Count > Max_Samples then
         return;
      end if;
      Count := Sample_Index (Raw.Sample_Count);

      for I in 1 .. Count loop
         --  1. This chunk is full: move to the next one. If an stsc run
         --  starts at it, that run now says how many samples it holds.
         if Left = 0 then
            if Chunk >= Raw.Chunk_Count then
               return;
            end if;
            Chunk := Chunk + 1;
            if Run < Raw.Chunk_Run_Count
              and then Raw.Chunk_Runs (Run + 1).First_Chunk = Natural (Chunk)
            then
               Run := Run + 1;
            end if;
            if Run = 0 or else Raw.Chunk_Runs (Run).Samples_Per_Chunk = 0 then
               return;
            end if;
            Left := Raw.Chunk_Runs (Run).Samples_Per_Chunk;
            Position := Raw.Chunk_Offsets (Chunk);
         end if;

         --  2. The size: one number for every sample, or one per sample.
         if Raw.Uniform_Size /= 0 then
            Size := Raw.Uniform_Size;
         else
            Size := Raw.Sizes (I);
         end if;

         --  3. The start: the sum of all earlier durations, converted.
         To_Framewise (C.Ticks, T.Timescale, Start, Good);
         if not Good then
            return;
         end if;

         --  4. Store it, and check it lies inside mdat (plan step 5).
         T.Samples (I) := (Offset => Position, Size => Size, Start => Start);
         if not Inside (T.Samples (I), Mdat_First, Mdat_Last) then
            return;
         end if;

         pragma Loop_Invariant
           (for all J in 1 .. I => Inside (T.Samples (J), Mdat_First, Mdat_Last));

         --  5. Get ready for sample I + 1. Its offset is only worked out
         --  if it is in this same chunk; a new chunk has its own offset.
         Left := Left - 1;
         if Left > 0 then
            if Size > Natural'Last - Position then
               return;
            end if;
            Position := Position + Size;
         end if;
         Advance (Raw, C, 1, Good);
         if not Good then
            return;
         end if;
      end loop;

      --  Every chunk filled, none left over. Tables_Agree already said
      --  so; this keeps the walk honest on its own.
      if Left /= 0 or else Chunk /= Raw.Chunk_Count then
         return;
      end if;

      T.Count := Count;
      Ok := True;
   end Resolve_Video;

   --  Audio: one Sample per chunk, holding all the PCM samples in it.
   procedure Resolve_Audio
     (Raw        : Raw_Track;
      Mdat_First : Natural;
      Mdat_Last  : Natural;
      T          : in out Track;
      C          : in out Clock;
      Ok         : out Boolean)
   is
      Run      : Sample_Index := 0;  --  the stsc run chunk K is in
      Used     : Natural := 0;       --  PCM samples in earlier chunks
      In_Chunk : Natural;            --  PCM samples in chunk K
      Bytes    : Natural;            --  their total size
      Size     : Natural;
      Start    : Time;
      Good     : Boolean;
   begin
      Ok := False;

      for K in 1 .. Raw.Chunk_Count loop
         --  1. Does a new stsc run start at this chunk?
         if Run < Raw.Chunk_Run_Count
           and then Raw.Chunk_Runs (Run + 1).First_Chunk = Natural (K)
         then
            Run := Run + 1;
         end if;
         if Run = 0 then
            return;
         end if;
         In_Chunk := Raw.Chunk_Runs (Run).Samples_Per_Chunk;
         if In_Chunk > Raw.Sample_Count - Used then
            return;
         end if;

         --  2. The chunk's bytes: In_Chunk times the uniform size, or the
         --  sum of its samples' sizes from the stsz list.
         if Raw.Uniform_Size /= 0 then
            if In_Chunk > Natural'Last / Raw.Uniform_Size then
               return;
            end if;
            Bytes := In_Chunk * Raw.Uniform_Size;
         else
            Bytes := 0;
            for J in 1 .. In_Chunk loop
               if Used + J > Natural (Raw.Size_Count) then
                  return;
               end if;
               Size := Raw.Sizes (Sample_Index (Used + J));
               if Size > Natural'Last - Bytes then
                  return;
               end if;
               Bytes := Bytes + Size;
            end loop;
         end if;

         --  3. The start of the chunk's first sample.
         To_Framewise (C.Ticks, T.Timescale, Start, Good);
         if not Good then
            return;
         end if;

         --  4. Store it, and check it lies inside mdat.
         T.Samples (K) := (Offset => Raw.Chunk_Offsets (K), Size => Bytes, Start => Start);
         if not Inside (T.Samples (K), Mdat_First, Mdat_Last) then
            return;
         end if;

         pragma Loop_Invariant
           (for all J in 1 .. K => Inside (T.Samples (J), Mdat_First, Mdat_Last));

         --  5. Step the clock over every PCM sample of this chunk.
         Used := Used + In_Chunk;
         Advance (Raw, C, In_Chunk, Good);
         if not Good then
            return;
         end if;
      end loop;

      if Used /= Raw.Sample_Count then
         return;
      end if;

      T.Count := Raw.Chunk_Count;
      Ok := True;
   end Resolve_Audio;

   procedure Resolve_Track
     (Raw        : Raw_Track;
      Mdat_First : Natural;
      Mdat_Last  : Natural;
      T          : in out Track;
      Track_End  : out Time;
      Ok         : out Boolean)
   is
      C : Clock;
   begin
      T.Codec := None;
      T.Count := 0;
      Track_End := 0;
      Ok := False;

      --  No such track in the file: an empty track is the right answer.
      if Raw.Codec = None then
         Ok := True;
         return;
      end if;

      --  Step 1: every time below is divided by the timescale.
      if Raw.Timescale = 0 then
         return;
      end if;

      --  Step 2: the tables must agree before any of them is used.
      if not Tables_Agree (Raw) then
         return;
      end if;

      --  Steps 3 and 4: the walk itself.
      T.Timescale := Raw.Timescale;
      if Raw.Codec = PCM_S16 then
         --  For PCM the mdhd timescale is the sample rate.
         T.Rate := Raw.Timescale;
         Resolve_Audio (Raw, Mdat_First, Mdat_Last, T, C, Ok);
      else
         Resolve_Video (Raw, Mdat_First, Mdat_Last, T, C, Ok);
      end if;

      --  After the walk, C.Ticks is when the last sample ends.
      if Ok then
         To_Framewise (C.Ticks, T.Timescale, Track_End, Ok);
      end if;

      if Ok then
         T.Codec := Raw.Codec;
      else
         T.Count := 0;
         Track_End := 0;
      end if;
   end Resolve_Track;

end Framewise.ISOBMFF.Resolve;
