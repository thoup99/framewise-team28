--  Pair P / week 3: tests for Framewise.ISOBMFF.Parse (sample resolution
--  and the mdat check) and Sample_At, on hand-built bytes.
--
--  With a file name as argument, it also parses that real proxy, cuts it
--  at random points, and prints one FRAME line per video sample and an
--  AT5 line for tests/compare_samples.sh to check against ffprobe.
with Ada.Command_Line;
with Ada.Exceptions;
with Ada.Numerics.Discrete_Random;
with Ada.Streams.Stream_IO;
with Ada.Text_IO;
with Framewise.ISOBMFF;
with Framewise.ISOBMFF.Boxes;
with Framewise.ISOBMFF.Resolve;
with Framewise.ISOBMFF.Tables;

procedure Parse_Tests is
   use Ada.Text_IO;
   use Framewise;
   use Framewise.ISOBMFF;

   subtype Int is Long_Long_Integer;

   Failures : Natural := 0;

   --  A File_Map is about 2 MB and a Track 1 MB, so they go on the heap.
   --  The no-heap rule is for src/, not for tests.
   type Map_Access is access File_Map;
   type Track_Access is access Track;
   M : constant Map_Access := new File_Map;

   Nothing : constant Byte_Array (1 .. 0) := [];
   Top     : constant Int := 2 ** 31 - 1;  --  Natural'Last: the largest U32 we accept

   --  Every hand-built file is: ftyp (12 bytes), then moov padded with a
   --  free box to exactly Moov_Size bytes, then the 8-byte mdat header.
   --  Fixing moov's size fixes where mdat's payload starts (Base), so the
   --  chunk offsets can be written before the moov is built. The mdat
   --  payload is not in the array at all: Parse only needs its header,
   --  and the File_Size passed to Parse says how big it is.
   Moov_Size : constant := 1_024;
   Base      : constant := 12 + Moov_Size + 8;

   procedure Check (Label_Text : String; Condition : Boolean);
   function B32 (Value : Int) return Byte_Array;
   function B32s (A, B : Int) return Byte_Array;
   function B32s (A, B, C : Int) return Byte_Array;
   function Tag (Kind : String) return Byte_Array;
   function Box (Kind : String; Payload : Byte_Array) return Byte_Array;
   function Table (Count : Int; Entries : Byte_Array) return Byte_Array;
   function Mdhd (Timescale : Int) return Byte_Array;
   function Trak_With
     (Handler, Codec : String; Mdhd_Box, Tables : Byte_Array) return Byte_Array;
   function Trak
     (Handler, Codec : String; Timescale : Int; Tables : Byte_Array) return Byte_Array;
   function Movie (Traks : Byte_Array; Mdat_Payload : Int) return Byte_Array;

   procedure Parse_Movie (Data : Byte_Array; Mdat_Payload : Int);
   --  Mdat_Payload defaults to the 1000 bytes Video_With uses.
   procedure Accepted (Label_Text : String; Data : Byte_Array; Mdat_Payload : Int := 1_000);
   procedure Rejected (Label_Text : String; Data : Byte_Array; Mdat_Payload : Int := 1_000);
   procedure Reject_Size (Label_Text : String; Data : Byte_Array; File_Size : Natural);

   procedure Test_Video;
   procedure Test_Audio;
   procedure Test_Inside;
   procedure Test_Cross_Checks;
   procedure Test_Tables_Agree;
   procedure Test_Overflow;
   procedure Test_Sample_At;
   procedure Test_Truncation;
   procedure Test_Every_Byte_Damaged;
   procedure Test_Real_File (Filename : String);

   procedure Check (Label_Text : String; Condition : Boolean) is
   begin
      Put_Line ((if Condition then "PASS " else "FAIL ") & Label_Text);
      if not Condition then
         Failures := Failures + 1;
      end if;
   end Check;

   function B32 (Value : Int) return Byte_Array is
     [Byte ((Value / 2 ** 24) mod 256), Byte ((Value / 2 ** 16) mod 256),
      Byte ((Value / 2 ** 8) mod 256), Byte (Value mod 256)];

   function B32s (A, B : Int) return Byte_Array is (B32 (A) & B32 (B));

   function B32s (A, B, C : Int) return Byte_Array is (B32 (A) & B32 (B) & B32 (C));

   function Tag (Kind : String) return Byte_Array is
     [Byte (Character'Pos (Kind (Kind'First))),
      Byte (Character'Pos (Kind (Kind'First + 1))),
      Byte (Character'Pos (Kind (Kind'First + 2))),
      Byte (Character'Pos (Kind (Kind'First + 3)))];

   function Box (Kind : String; Payload : Byte_Array) return Byte_Array is
     (B32 (Int (Payload'Length) + 8) & Tag (Kind) & Payload);

   --  The usual table layout: version and flags = 0, count, then entries.
   function Table (Count : Int; Entries : Byte_Array) return Byte_Array is
     (B32s (0, Count) & Entries);

   --  Version 0: version/flags, creation, modification, timescale,
   --  duration, then language and quality.
   function Mdhd (Timescale : Int) return Byte_Array is
     (Box ("mdhd", B32s (0, 0, 0) & B32s (Timescale, 0) & B32 (0)));

   --  Tables is stts & stsc & stsz & stco (or co64), already boxed.
   function Trak_With
     (Handler, Codec : String; Mdhd_Box, Tables : Byte_Array) return Byte_Array
   is (Box ("trak", Box ("tkhd", [1 .. 4 => 0])
            & Box ("mdia", Mdhd_Box
                   & Box ("hdlr", B32 (0) & Tag ("mhlr") & Tag (Handler) & B32 (0))
                   & Box ("minf", Box ("stbl", Box ("stsd", Table (1, Box (Codec, [1 .. 8 => 0])))
                                       & Tables)))));

   function Trak
     (Handler, Codec : String; Timescale : Int; Tables : Byte_Array) return Byte_Array
   is (Trak_With (Handler, Codec, Mdhd (Timescale), Tables));

   function Movie (Traks : Byte_Array; Mdat_Payload : Int) return Byte_Array is
   begin
      --  If this fails, a test's tracks are too big: raise Moov_Size.
      pragma Assert (Traks'Length <= Moov_Size - 16);
      return Box ("ftyp", Tag ("qt  "))
        & Box ("moov", Traks & Box ("free", [1 .. Moov_Size - 16 - Traks'Length => 0]))
        & B32 (Mdat_Payload + 8) & Tag ("mdat");
   end Movie;

   --  Parse a Movie as if the whole file, mdat payload included, existed.
   procedure Parse_Movie (Data : Byte_Array; Mdat_Payload : Int) is
   begin
      Parse (Data, Data'Length + Natural (Mdat_Payload), M.all);
   end Parse_Movie;

   --  An exception inside Parse (including a failed Post, since the
   --  library is built with -gnata) lands in the handler and is a FAIL.
   procedure Accepted (Label_Text : String; Data : Byte_Array; Mdat_Payload : Int := 1_000) is
   begin
      Parse_Movie (Data, Mdat_Payload);
      Check (Label_Text, M.Ok and then Well_Formed (M.all));
   exception
      when E : others =>
         Check (Label_Text & " raised " & Ada.Exceptions.Exception_Name (E), False);
   end Accepted;

   procedure Rejected (Label_Text : String; Data : Byte_Array; Mdat_Payload : Int := 1_000) is
   begin
      Reject_Size (Label_Text, Data, Data'Length + Natural (Mdat_Payload));
   end Rejected;

   procedure Reject_Size (Label_Text : String; Data : Byte_Array; File_Size : Natural) is
   begin
      Parse (Data, File_Size, M.all);
      Check (Label_Text, not M.Ok and then M.Video.Count = 0 and then M.Audio.Count = 0);
   exception
      when E : others =>
         Check (Label_Text & " raised " & Ada.Exceptions.Exception_Name (E), False);
   end Reject_Size;

   ---------------------------------------------------------------------
   --  The good tracks. Each test changes one thing about them.
   ---------------------------------------------------------------------

   --  Video: 6 frames, timescale 15360 (what ffmpeg writes for 30 fps).
   --  stts, 3 runs:  frames 1-3 last 512, 4-5 last 1024, 6 lasts 256.
   --  stsc, 3 runs:  chunk 1 has 2 frames, chunks 2-3 have 1, chunk 4
   --                 (the last run reaching to the last chunk) has 2.
   Video_Stts : constant Byte_Array :=
     Box ("stts", Table (3, B32s (3, 512) & B32s (2, 1_024) & B32s (1, 256)));
   Video_Stsc : constant Byte_Array :=
     Box ("stsc", Table (3, B32s (1, 2, 1) & B32s (2, 1, 1) & B32s (4, 2, 1)));
   Video_Stsz : constant Byte_Array :=
     Box ("stsz", B32s (0, 0, 6) & B32s (10, 20, 30) & B32s (40, 50, 60));

   --  The 4 chunks, 100 bytes apart, the first at At_Base.
   function Video_Stco (At_Base : Int) return Byte_Array is
     (Box ("stco", Table (4, B32s (At_Base, At_Base + 100)
                          & B32s (At_Base + 200, At_Base + 300))));

   function Video (At_Base : Int := Base) return Byte_Array is
     (Trak ("vide", "jpeg", 15_360, Video_Stts & Video_Stsc & Video_Stsz
                                    & Video_Stco (At_Base)));

   --  What Parse must make of Video. Start = ticks * 90000 / 15360, so
   --  512 ticks are 3000 Framewise ticks. It ends at 3840 ticks = 22500.
   Want_Video : constant array (Sample_Index range 1 .. 6) of Sample :=
     [(Base, 10, 0), (Base + 10, 20, 3_000),           --  chunk 1
      (Base + 100, 30, 6_000),                         --  chunk 2
      (Base + 200, 40, 9_000),                         --  chunk 3
      (Base + 300, 50, 15_000), (Base + 350, 60, 21_000)];  --  chunk 4

   --  Audio: 1600 PCM samples of 2 bytes at 48 kHz. stsc: chunk 1 holds
   --  800, chunks 2 and 3 hold 400 each. Offsets in co64.
   Audio_Stts : constant Byte_Array := Box ("stts", Table (1, B32s (1_600, 1)));
   Audio_Stsc : constant Byte_Array :=
     Box ("stsc", Table (2, B32s (1, 800, 1) & B32s (2, 400, 1)));
   Audio_Stsz : constant Byte_Array := Box ("stsz", B32s (0, 2, 1_600));

   function Audio (At_Base : Int) return Byte_Array is
     (Trak ("soun", "sowt", 48_000, Audio_Stts & Audio_Stsc & Audio_Stsz
            & Box ("co64", Table (3, B32s (0, At_Base) & B32s (0, At_Base + 1_600)
                                  & B32s (0, At_Base + 2_400)))));

   --  Video with other tables, in a file with a 1000-byte mdat.
   function Video_With
     (Stts, Stsc, Stsz, Stco : Byte_Array; Timescale : Int := 15_360) return Byte_Array
   is (Movie (Trak ("vide", "jpeg", Timescale, Stts & Stsc & Stsz & Stco), 1_000));

   ---------------------------------------------------------------------

   procedure Test_Video is
   begin
      Accepted ("video, multi-entry stts and stsc", Movie (Video, 1_000), 1_000);
      if not M.Ok then
         return;
      end if;

      Check ("video codec and timescale",
             M.Video.Codec = JPEG and then M.Video.Timescale = 15_360);
      Check ("video sample count", M.Video.Count = 6);
      for I in Want_Video'Range loop
         Check ("video sample" & I'Image & " offset, size, start",
                M.Video.Samples (I) = Want_Video (I));
      end loop;
      Check ("mdat range, from 0", M.Mdat_First = Base and then M.Mdat_Last = Base + 999);
      Check ("length is when the last frame ends", M.Length = 22_500);
      Check ("no audio track", M.Audio.Codec = None and then M.Audio.Count = 0);

      --  The trap: one stsc run covers every chunk to the last one.
      Accepted ("one stsc run for all chunks",
                Video_With (Box ("stts", Table (1, B32s (6, 512))),
                            Box ("stsc", Table (1, B32s (1, 2, 1))), Video_Stsz,
                            Box ("stco", Table (3, B32s (Base, Base + 100)
                                                & B32 (Base + 200)))));
      Check ("one stsc run: 2 frames in every chunk",
             M.Ok and then M.Video.Count = 6
             and then M.Video.Samples (4) = (Base + 130, 40, 9_000)
             and then M.Video.Samples (6) = (Base + 250, 60, 15_000));

      --  A run with count 0 adds nothing and is skipped.
      Accepted ("stts run with count 0",
                Video_With (Box ("stts", Table (3, B32s (3, 512) & B32s (0, 99)
                                                & B32s (3, 512))),
                            Video_Stsc, Video_Stsz, Video_Stco (Base)));
      Check ("count-0 run changes no time",
             M.Ok and then M.Video.Samples (4).Start = 9_000
             and then M.Length = 18_000);

      --  A fixed size in stsz instead of a list.
      Accepted ("video with a uniform stsz",
                Video_With (Video_Stts, Video_Stsc, Box ("stsz", B32s (0, 7, 6)),
                            Video_Stco (Base)));
      Check ("uniform size: offsets step by it",
             M.Ok and then M.Video.Samples (2) = (Base + 7, 7, 3_000)
             and then M.Video.Samples (6) = (Base + 307, 7, 21_000));

      Accepted ("empty video track", Video_With (Box ("stts", Table (0, Nothing)),
                Box ("stsc", Table (0, Nothing)), Box ("stsz", B32s (0, 0, 0)),
                Box ("stco", Table (0, Nothing))));
      Check ("empty track has no samples and length 0",
             M.Ok and then M.Video.Count = 0 and then M.Length = 0
             and then Sample_At (M.Video, 0) = 0);
   end Test_Video;

   procedure Test_Audio is
      List : constant Byte_Array :=
        Trak ("soun", "twos", 90_000, Box ("stts", Table (1, B32s (4, 1)))
              & Box ("stsc", Table (1, B32s (1, 2, 1)))
              & Box ("stsz", B32s (0, 0, 4) & B32s (2, 4, 6) & B32 (8))
              & Box ("stco", Table (2, B32s (Base, Base + 6))));
   begin
      Accepted ("audio only", Movie (Audio (Base), 3_200), 3_200);
      Check ("audio: one sample per chunk",
             M.Ok and then M.Audio.Codec = PCM_S16 and then M.Audio.Count = 3);
      --  800 ticks at 48 kHz are 1500 Framewise ticks.
      Check ("audio chunk 1", M.Ok and then M.Audio.Samples (1) = (Base, 1_600, 0));
      Check ("audio chunk 2", M.Ok and then M.Audio.Samples (2) = (Base + 1_600, 800, 1_500));
      Check ("audio chunk 3", M.Ok and then M.Audio.Samples (3) = (Base + 2_400, 800, 2_250));
      Check ("audio rate and length",
             M.Ok and then M.Audio.Rate = 48_000 and then M.Length = 3_000);

      Accepted ("video and audio", Movie (Video & Audio (Base + 1_000), 4_200), 4_200);
      Check ("both tracks, length of the longer",
             M.Ok and then M.Video.Count = 6 and then M.Audio.Count = 3
             and then M.Audio.Samples (2).Offset = Base + 2_600
             and then M.Length = 22_500);

      Accepted ("audio with an stsz list", Movie (List, 100), 100);
      Check ("audio chunk size is the sum of its samples",
             M.Ok and then M.Audio.Count = 2
             and then M.Audio.Samples (1) = (Base, 6, 0)
             and then M.Audio.Samples (2) = (Base + 6, 14, 2));
   end Test_Audio;

   procedure Test_Inside is
      Good : constant Byte_Array := Movie (Video, 1_000);
   begin
      --  Want_Video's last frame is Base + 350 .. Base + 409.
      Accepted ("last frame ends on mdat's last byte", Movie (Video, 410), 410);
      Rejected ("last frame one byte past mdat", Movie (Video, 409), 409);
      Rejected ("chunk one byte before mdat", Movie (Video (Base - 1), 1_000), 1_000);
      Rejected ("chunk at offset 0, inside ftyp", Movie (Video (0), 1_000), 1_000);
      Rejected ("chunk far past the file", Movie (Video (Base + 5_000), 1_000), 1_000);
      Rejected ("audio chunk past mdat", Movie (Audio (Base), 3_199), 3_199);
      Rejected ("good video, audio outside mdat",
                Movie (Video & Audio (Base + 1_000), 4_199), 4_199);
      Rejected ("empty mdat", Movie (Video, 0), 0);

      --  Where mdat is. Parse needs its header in the input.
      Reject_Size ("no mdat", Good (1 .. Good'Last - 8), Good'Length - 8);
      Reject_Size ("mdat header not in the input", Good (1 .. Good'Last - 8),
                   Good'Length + 1_000);
      Reject_Size ("mdat header cut in half", Good (1 .. Good'Last - 4),
                   Good'Length + 1_000);

      declare
         --  mdat first (no faststart): it is fine as long as the input holds it.
         Late : constant Byte_Array :=
           Box ("ftyp", Tag ("qt  ")) & Box ("mdat", [1 .. 1_000 => 0])
           & Box ("moov", Video (20));
      begin
         Reject_Size ("moov after mdat, only up to mdat's header",
                      Late (1 .. 20), Late'Length);
         Parse (Late, Late'Length, M.all);
         Check ("moov after mdat, whole file",
                M.Ok and then M.Mdat_First = 20 and then M.Mdat_Last = 1_019
                and then M.Video.Samples (1).Offset = 20);
      end;

      declare
         --  mdat with size 0: it runs to the end of the file.
         To_End : constant Byte_Array := Good (1 .. Good'Last - 8) & B32 (0) & Tag ("mdat");
      begin
         Parse (To_End, To_End'Length + 1_000, M.all);
         Check ("mdat with size 0 reaches the end of the file",
                M.Ok and then M.Mdat_Last = Base + 999);
      end;
   end Test_Inside;

   --  Step 2: tables that do not fit together.
   procedure Test_Cross_Checks is
      Stco : constant Byte_Array := Video_Stco (Base);
   begin
      Rejected ("timescale 0", Movie (Trak ("vide", "jpeg", 0, Video_Stts & Video_Stsc
                                            & Video_Stsz & Stco), 1_000), 1_000);
      Rejected ("no mdhd", Movie (Trak_With ("vide", "jpeg", Nothing, Video_Stts & Video_Stsc
                                             & Video_Stsz & Stco), 1_000), 1_000);

      Rejected ("stts adds up to fewer samples than stsz",
                Video_With (Box ("stts", Table (1, B32s (5, 512))), Video_Stsc, Video_Stsz, Stco));
      Rejected ("stts adds up to more samples than stsz",
                Video_With (Box ("stts", Table (2, B32s (6, 512) & B32s (1, 512))),
                            Video_Stsc, Video_Stsz, Stco));
      Rejected ("stts counts that would overflow a sum",
                Video_With (Box ("stts", Table (2, B32s (Top, 1) & B32s (Top, 1))),
                            Video_Stsc, Video_Stsz, Stco));

      Rejected ("stsc first run not at chunk 1",
                Video_With (Video_Stts, Box ("stsc", Table (2, B32s (2, 2, 1) & B32s (3, 2, 1))),
                            Video_Stsz, Stco));
      Rejected ("stsc runs out of order",
                Video_With (Video_Stts, Box ("stsc", Table (3, B32s (1, 2, 1) & B32s (4, 2, 1)
                                                        & B32s (2, 1, 1))),
                            Video_Stsz, Stco));
      Rejected ("stsc two runs on the same chunk",
                Video_With (Video_Stts, Box ("stsc", Table (3, B32s (1, 2, 1) & B32s (1, 1, 1)
                                                        & B32s (4, 2, 1))),
                            Video_Stsz, Stco));
      Rejected ("stsc run on a chunk that does not exist",
                Video_With (Video_Stts, Box ("stsc", Table (3, B32s (1, 2, 1) & B32s (2, 1, 1)
                                                        & B32s (5, 2, 1))),
                            Video_Stsz, Stco));
      Rejected ("stsc with 0 samples per chunk",
                Video_With (Video_Stts, Box ("stsc", Table (3, B32s (1, 2, 1) & B32s (2, 0, 1)
                                                        & B32s (4, 2, 1))),
                            Video_Stsz, Stco));
      Rejected ("stsc puts more samples in the chunks than stsz has",
                Video_With (Video_Stts, Box ("stsc", Table (1, B32s (1, 2, 1))), Video_Stsz,
                            Stco));
      Rejected ("stsc puts fewer samples in the chunks than stsz has",
                Video_With (Video_Stts, Box ("stsc", Table (1, B32s (1, 1, 1))), Video_Stsz,
                            Stco));
      Rejected ("stsc samples that would overflow a product",
                Video_With (Video_Stts, Box ("stsc", Table (1, B32s (1, Top, 1))), Video_Stsz,
                            Stco));
      Rejected ("no stsc run, but chunks",
                Video_With (Box ("stts", Table (0, Nothing)), Box ("stsc", Table (0, Nothing)),
                            Box ("stsz", B32s (0, 0, 0)), Stco));
      Rejected ("stsc run, but no chunks",
                Video_With (Video_Stts, Video_Stsc, Video_Stsz, Box ("stco", Table (0, Nothing))));
      Rejected ("audio stts does not add up",
                Movie (Trak ("soun", "sowt", 48_000, Box ("stts", Table (1, B32s (1_599, 1)))
                             & Audio_Stsc & Audio_Stsz
                             & Box ("stco", Table (3, B32s (Base, Base + 1_600)
                                                   & B32 (Base + 2_400)))), 3_200), 3_200);
   end Test_Cross_Checks;

   --  The same cross-checks, straight on Tables_Agree. Through Parse, the
   --  walk's own guards would also reject most of these files, so only
   --  this test shows Tables_Agree itself catches them.
   procedure Test_Tables_Agree is
      use Framewise.ISOBMFF.Tables;
      type Raw_Access is access Raw_Track;
      R : constant Raw_Access := new Raw_Track;

      --  The good video tables from above, as Read_Tables stores them.
      procedure Reset;
      procedure Reset is
      begin
         R.Sample_Count := 6;
         R.Uniform_Size := 0;
         R.Size_Count := 6;
         R.Time_Run_Count := 3;
         R.Time_Runs (1 .. 3) := [(3, 512), (2, 1_024), (1, 256)];
         R.Chunk_Run_Count := 3;
         R.Chunk_Runs (1 .. 3) := [(1, 2), (2, 1), (4, 2)];
         R.Chunk_Count := 4;
      end Reset;

      procedure Agree (Label_Text : String; Want : Boolean);
      procedure Agree (Label_Text : String; Want : Boolean) is
      begin
         Check ("Tables_Agree: " & Label_Text, Resolve.Tables_Agree (R.all) = Want);
         Reset;
      end Agree;
   begin
      Reset;
      Agree ("good tables", True);

      R.Time_Runs (3).Sample_Count := 0;
      Agree ("stts one sample short", False);
      R.Time_Runs (3).Sample_Count := 2;
      Agree ("stts one sample over", False);
      R.Size_Count := 5;
      Agree ("stsz list one size short", False);

      R.Chunk_Runs (3).Samples_Per_Chunk := 1;
      Agree ("stsc one sample short", False);
      R.Chunk_Runs (3).Samples_Per_Chunk := 3;
      Agree ("stsc one sample over", False);
      R.Chunk_Count := 5;
      Agree ("last stsc run reaches one more chunk", False);
      R.Chunk_Runs (1).First_Chunk := 2;
      Agree ("stsc not starting at chunk 1", False);
      R.Chunk_Runs (2).First_Chunk := 4;
      R.Chunk_Runs (3).First_Chunk := 2;
      Agree ("stsc out of order", False);
      R.Chunk_Runs (3).First_Chunk := 2;
      Agree ("stsc two runs on one chunk", False);
      R.Chunk_Runs (3).First_Chunk := 5;
      Agree ("stsc run past the last chunk", False);
      R.Chunk_Runs (2).Samples_Per_Chunk := 0;
      Agree ("stsc 0 samples per chunk", False);
      R.Chunk_Run_Count := 0;
      Agree ("no stsc runs", False);

      R.Sample_Count := 0;
      R.Size_Count := 0;
      R.Time_Run_Count := 0;
      R.Chunk_Run_Count := 0;
      R.Chunk_Count := 0;
      Agree ("all empty", True);
      R.Chunk_Count := 0;
      R.Chunk_Run_Count := 1;
      Agree ("stsc run but no chunks", False);
   end Test_Tables_Agree;

   --  Sums and products that do not fit their type must give Ok = False,
   --  never an exception. Big mdats cost nothing: only File_Size says so.
   procedure Test_Overflow is
      Half : constant Int := 2 ** 30;

      --  One audio chunk of Count PCM samples, each Size bytes and
      --  Ticks long, in an mdat of Mdat bytes.
      function Pcm (Count, Size, Ticks, Timescale, Mdat : Int) return Byte_Array is
        (Movie (Trak ("soun", "sowt", Timescale, Box ("stts", Table (1, B32s (Count, Ticks)))
                      & Box ("stsc", Table (1, B32s (1, Count, 1)))
                      & Box ("stsz", B32s (0, Size, Count))
                      & Box ("stco", Table (1, B32 (Base)))), Mdat));

      --  A video in a file of exactly Natural'Last bytes: ftyp, moov,
      --  then an mdat with size 0, so mdat runs to the end of the file.
      function Huge (Tables : Byte_Array) return Byte_Array is
        (Box ("ftyp", Tag ("qt  ")) & Box ("moov", Trak ("vide", "jpeg", 30, Tables))
         & B32 (0) & Tag ("mdat"));

      Last : constant Int := Int (Natural'Last) - 1;  --  last byte of that file, from 0
   begin
      --  Time. At timescale 1, Top ticks are Top * 90000 Framewise ticks.
      Accepted ("largest stts delta, small count",
                Video_With (Box ("stts", Table (1, B32s (2, Top))),
                            Box ("stsc", Table (1, B32s (1, 2, 1))), Box ("stsz", B32s (0, 1, 2)),
                            Box ("stco", Table (1, B32 (Base))), Timescale => 1), 1_000);
      Check ("largest stts delta gives exact times",
             M.Ok and then M.Video.Samples (2).Start = Time (Top) * Timebase
             and then M.Length = 2 * Time (Top) * Timebase);
      Rejected ("frame start too large for Time",
                Video_With (Box ("stts", Table (1, B32s (30_000, Top))),
                            Box ("stsc", Table (1, B32s (1, 30_000, 1))),
                            Box ("stsz", B32s (0, 1, 30_000)),
                            Box ("stco", Table (1, B32 (Base))), Timescale => 1), 1_000);
      Rejected ("audio track end too large for Time", Pcm (Half, 1, Top, 1, Half), Half);
      Accepted ("audio track of 2**30 samples", Pcm (Half, 1, 1, 48_000, Half), Half);
      Check ("2**30 samples at 48 kHz", M.Ok and then M.Length = Time (Half) * 90_000 / 48_000);

      --  Bytes.
      Rejected ("audio chunk bytes overflow (uniform size)", Pcm (Half, 4, 1, 48_000, 1_000),
                1_000);
      Rejected ("audio chunk bytes overflow (size list)",
                Movie (Trak ("soun", "sowt", 48_000, Box ("stts", Table (1, B32s (2, 1)))
                             & Box ("stsc", Table (1, B32s (1, 2, 1)))
                             & Box ("stsz", B32s (0, 0, 2) & B32s (Top, Top))
                             & Box ("stco", Table (1, B32 (Base)))), 1_000), 1_000);
      Rejected ("frame size Natural'Last",
                Video_With (Box ("stts", Table (1, B32s (1, 1))),
                            Box ("stsc", Table (1, B32s (1, 1, 1))), Box ("stsz", B32s (0, Top, 1)),
                            Box ("stco", Table (1, B32 (Base)))), 1_000);

      --  Offsets at the very end of the biggest file Natural can describe.
      declare
         One_Frame : constant Byte_Array :=
           Huge (Box ("stts", Table (1, B32s (1, 1))) & Box ("stsc", Table (1, B32s (1, 1, 1)))
                 & Box ("stsz", B32s (0, 1, 1)) & Box ("stco", Table (1, B32 (Last))));
         Two_Frames : constant Byte_Array :=
           Huge (Box ("stts", Table (1, B32s (2, 1))) & Box ("stsc", Table (1, B32s (1, 2, 1)))
                 & Box ("stsz", B32s (0, 1, 2)) & Box ("stco", Table (1, B32 (Last))));
         At_Top : constant Byte_Array :=
           Huge (Box ("stts", Table (1, B32s (1, 1))) & Box ("stsc", Table (1, B32s (1, 1, 1)))
                 & Box ("stsz", B32s (0, 1, 1)) & Box ("stco", Table (1, B32 (Top))));
      begin
         Parse (One_Frame, Natural'Last, M.all);
         Check ("frame on the last byte of a Natural'Last file",
                M.Ok and then M.Mdat_Last = Natural (Last)
                and then M.Video.Samples (1).Offset = Natural (Last));
         Reject_Size ("second frame would start past the file", Two_Frames, Natural'Last);
         Reject_Size ("chunk offset Natural'Last", At_Top, Natural'Last);
      end;
   end Test_Overflow;

   procedure Test_Sample_At is
      T : constant Track_Access := new Track;

      procedure Expect (Label_Text : String; At_Time : Time; Want : Sample_Index);
      procedure Expect (Label_Text : String; At_Time : Time; Want : Sample_Index) is
         Got : constant Sample_Index := Sample_At (T.all, At_Time);
      begin
         Check ("Sample_At " & Label_Text & ": got" & Got'Image, Got = Want);
      end Expect;

      Wrong : Natural := 0;
   begin
      T.Count := 0;
      Expect ("empty track", 0, 0);
      Expect ("empty track, Time'Last", Time'Last, 0);

      T.Count := 4;
      T.Samples (1).Start := 3_000;
      T.Samples (2).Start := 6_000;
      T.Samples (3).Start := 9_000;
      T.Samples (4).Start := 12_000;
      Expect ("at 0, before the first sample", 0, 0);
      Expect ("just before the first sample", 2_999, 0);
      Expect ("exactly on the first start", 3_000, 1);
      Expect ("exactly on a middle start", 9_000, 3);
      Expect ("between two starts", 7_000, 2);
      Expect ("just before a start", 8_999, 2);
      Expect ("exactly on the last start", 12_000, 4);
      Expect ("after the last start", 12_001, 4);
      Expect ("at Time'Last", Time'Last, 4);

      T.Count := 1;
      T.Samples (1).Start := 0;
      Expect ("one sample, at 0", 0, 1);
      Expect ("one sample, after it", 100, 1);

      --  Equal starts (a duration of 0): the last of them wins.
      T.Count := 4;
      T.Samples (1 .. 4) := [(0, 0, 0), (0, 0, 3_000), (0, 0, 3_000), (0, 0, 6_000)];
      Expect ("equal starts", 3_000, 3);

      --  Every sample of a full track, on its start and halfway to the next.
      T.Count := Max_Samples;
      for I in 1 .. T.Count loop
         T.Samples (I).Start := Time (I - 1) * 3_000;
      end loop;
      for I in 1 .. T.Count loop
         if Sample_At (T.all, T.Samples (I).Start) /= I
           or else Sample_At (T.all, T.Samples (I).Start + 1_500) /= I
         then
            Wrong := Wrong + 1;
         end if;
      end loop;
      Check ("Sample_At on all" & Max_Samples'Image & " samples of a full track:"
             & Wrong'Image & " wrong", Wrong = 0);

      --  And on a parsed file.
      Parse_Movie (Movie (Video, 1_000), 1_000);
      Check ("Sample_At on a parsed file",
             M.Ok and then Sample_At (M.Video, 9_000) = 4
             and then Sample_At (M.Video, 14_999) = 4
             and then Sample_At (M.Video, 99_999) = 6);
   end Test_Sample_At;

   --  Cut the input at every byte. Nothing is accepted until the input
   --  holds mdat's header, whatever File_Size says.
   procedure Test_Truncation is
      Good   : constant Byte_Array := Movie (Video & Audio (Base + 1_000), 4_200);
      Raised : Natural := 0;
      Took   : Natural := 0;

      procedure Try (N, File_Size : Natural);
      procedure Try (N, File_Size : Natural) is
      begin
         Parse (Good (1 .. N), File_Size, M.all);
         if M.Ok then
            Took := Took + 1;
         end if;
      exception
         when others =>
            Raised := Raised + 1;
      end Try;
   begin
      for N in 0 .. Good'Last - 1 loop
         Try (N, N);                        --  the file really is this short
         Try (N, Good'Length + 4_200);      --  only the input is short
      end loop;
      Check ("cut at every byte: never raises," & Raised'Image & " raised", Raised = 0);
      Check ("cut at every byte: never accepted," & Took'Image & " accepted", Took = 0);
      Accepted ("not cut", Good, 4_200);
   end Test_Truncation;

   --  Replace each byte of the tracks and the mdat header with values
   --  that tend to cause trouble. Ok or not, Parse must never raise, and
   --  when Ok the Post (checked at run time) and Well_Formed must hold.
   --  The free box's zero padding is skipped: changing it changes nothing.
   procedure Test_Every_Byte_Damaged is
      Traks   : constant Byte_Array := Video & Audio (Base + 1_000);
      Good    : constant Byte_Array := Movie (Traks, 4_200);
      Values  : constant Byte_Array := [0, 1, 16#7F#, 16#80#, 16#FF#];
      Damaged : Byte_Array := Good;
      Calls   : Natural := 0;
      Raised  : Natural := 0;
      Bad     : Natural := 0;
   begin
      for I in Damaged'Range loop
         if I <= 20 + Traks'Length + 8 or else I > Good'Last - 8 then
            for V of Values loop
               Damaged (I) := V;
               begin
                  Parse_Movie (Damaged, 4_200);
                  if M.Ok and then not Well_Formed (M.all) then
                     Bad := Bad + 1;
                  end if;
               exception
                  when others =>
                     Raised := Raised + 1;
               end;
               Calls := Calls + 1;
            end loop;
            Damaged (I) := Good (I);
         end if;
      end loop;
      Check ("damaged bytes never raise:" & Calls'Image & " tries," & Raised'Image & " raised,"
             & Bad'Image & " not well formed", Raised = 0 and then Bad = 0);
   end Test_Every_Byte_Damaged;

   --  Runs against a real proxy. See tests/compare_samples.sh.
   procedure Test_Real_File (Filename : String) is
      use Ada.Streams;

      type Raw_Access is access Stream_Element_Array;
      type Bytes_Access is access Byte_Array;
      package Random_Natural is new Ada.Numerics.Discrete_Random (Natural);

      File   : Stream_IO.File_Type;
      Raw    : Raw_Access;
      Data   : Bytes_Access;
      Last   : Stream_Element_Offset;
      Mdat   : Boxes.Box_Header;
      Found  : Boolean;
      Gen    : Random_Natural.Generator;
      Header : Natural;  --  last byte of mdat's header: what Decode will read
      At_5   : Sample_Index;
   begin
      Stream_IO.Open (File, Stream_IO.In_File, Filename);
      Raw := new Stream_Element_Array (1 .. Stream_Element_Offset (Stream_IO.Size (File)));
      Stream_IO.Read (File, Raw.all, Last);
      Stream_IO.Close (File);

      Data := new Byte_Array (1 .. Natural (Last));
      for I in Data'Range loop
         Data (I) := Byte (Raw (Stream_Element_Offset (I)));
      end loop;

      Boxes.Find_Child (Data.all, 1, Data'Last, "mdat", Mdat, Found);
      Check ("real file has an mdat", Found);
      if not Found then
         return;
      end if;
      Header := Mdat.Box_First + Mdat.Header_Length - 1;

      --  Option 1: Parse gets the file only up to the end of mdat's header.
      Parse (Data (1 .. Header), Data'Length, M.all);
      Check ("real file parsed", M.Ok and then Well_Formed (M.all));
      Check ("real file has video", M.Ok and then M.Video.Codec = JPEG
             and then M.Video.Count > 0);
      if M.Ok then
         for I in 1 .. M.Video.Count loop
            Put_Line ("FRAME" & I'Image & M.Video.Samples (I).Offset'Image
                      & M.Video.Samples (I).Size'Image & M.Video.Samples (I).Start'Image);
         end loop;
         At_5 := Sample_At (M.Video, 5 * Timebase);
         Put_Line ("AT5" & At_5'Image);
         Put_Line ("LENGTH" & M.Length'Image);
      end if;

      --  The plan's truncation test: a file cut at ten random points. The
      --  points are printed, so a failure can be repeated by hand.
      Random_Natural.Reset (Gen);
      for K in 1 .. 10 loop
         declare
            N : constant Natural := Random_Natural.Random (Gen) mod Data'Length;
         begin
            Reject_Size ("real file cut at" & N'Image,
                         Data (1 .. Natural'Min (N, Header)), N);
         end;
      end loop;

      --  Ten more inside moov and the mdat header, where the parsing is.
      for K in 1 .. 10 loop
         declare
            N : constant Natural := Random_Natural.Random (Gen) mod Header;
         begin
            Reject_Size ("real header cut at" & N'Image, Data (1 .. N), N);
            Reject_Size ("real header cut, true size, at" & N'Image, Data (1 .. N), Data'Length);
         end;
      end loop;
   exception
      when E : others =>
         Check ("could not test " & Filename & ": " & Ada.Exceptions.Exception_Name (E), False);
   end Test_Real_File;

begin
   Test_Video;
   Test_Audio;
   Test_Inside;
   Test_Cross_Checks;
   Test_Tables_Agree;
   Test_Overflow;
   Test_Sample_At;
   Test_Truncation;
   Test_Every_Byte_Damaged;

   for I in 1 .. Ada.Command_Line.Argument_Count loop
      Test_Real_File (Ada.Command_Line.Argument (I));
   end loop;

   if Failures = 0 then
      Put_Line ("all ISOBMFF parse tests passed");
   else
      Put_Line (Failures'Image & " parse test failure(s)");
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;
end Parse_Tests;
