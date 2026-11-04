--  Pair P / week 2: tests for Framewise.ISOBMFF.Tables on hand-built bytes.
--
--  With a file name as argument, it also reads that real MOV, cuts it at
--  ten points, and prints one COUNTS line per track for
--  tests/compare_tables.sh to check against ffprobe.
with Ada.Command_Line;
with Ada.Exceptions;
with Ada.Streams.Stream_IO;
with Ada.Text_IO;
with Framewise.ISOBMFF;
with Framewise.ISOBMFF.Boxes;
with Framewise.ISOBMFF.Tables;

procedure Table_Reader_Tests is
   use Ada.Text_IO;
   use Framewise.ISOBMFF;
   use Framewise.ISOBMFF.Tables;

   Failures : Natural := 0;
   Ok       : Boolean;

   --  Raw_Tables is about 3 MB and this test file builds big arrays too, so
   --  it goes on the heap. The no-heap rule is for src/, not for tests.
   type Tables_Access is access Raw_Tables;
   T : constant Tables_Access := new Raw_Tables;

   Nothing   : constant Byte_Array (1 .. 0) := [];
   Too_Large : constant := 2 ** 31;  --  first value that does not fit Natural

   procedure Check (Label_Text : String; Condition : Boolean);
   function B32 (Value : Long_Long_Integer) return Byte_Array;
   function B32s (A, B : Long_Long_Integer) return Byte_Array;
   function B32s (A, B, C : Long_Long_Integer) return Byte_Array;
   function Tag (Kind : String) return Byte_Array;
   function Box (Kind : String; Payload : Byte_Array) return Byte_Array;
   function Table (Count : Long_Long_Integer; Entries : Byte_Array) return Byte_Array;
   function Stsd (Codec : String) return Byte_Array;
   function Hdlr (Handler : String) return Byte_Array;
   function Trak (Handler : String; Stbl_Payload : Byte_Array) return Byte_Array;
   function Trak_Stbl
     (Handler, Codec            : String;
      Stts, Stsc, Stsz, Offsets : Byte_Array) return Byte_Array;
   function Moov (Children : Byte_Array) return Byte_Array;

   procedure Accepted (Label_Text : String; Data : Byte_Array);
   procedure Rejected (Label_Text : String; Data : Byte_Array);
   procedure Reject_Size (Label_Text : String; Data : Byte_Array; File_Size : Natural);

   procedure Test_Good_File;
   procedure Test_Shapes;
   procedure Test_Missing_Boxes;
   procedure Test_Stsd;
   procedure Test_Bad_Tables;
   procedure Test_Max_Samples;
   procedure Test_Audio_Rule;
   procedure Test_Tracks;
   procedure Test_Timescale;
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

   --  Long_Long_Integer so a test can also write 2**31, which Natural
   --  cannot hold. Those are the bad values the reader must refuse.
   function B32 (Value : Long_Long_Integer) return Byte_Array is
     [Byte ((Value / 2 ** 24) mod 256), Byte ((Value / 2 ** 16) mod 256),
      Byte ((Value / 2 ** 8) mod 256), Byte (Value mod 256)];

   function B32s (A, B : Long_Long_Integer) return Byte_Array is (B32 (A) & B32 (B));

   function B32s (A, B, C : Long_Long_Integer) return Byte_Array is
     (B32 (A) & B32 (B) & B32 (C));

   function Tag (Kind : String) return Byte_Array is
     [Byte (Character'Pos (Kind (Kind'First))),
      Byte (Character'Pos (Kind (Kind'First + 1))),
      Byte (Character'Pos (Kind (Kind'First + 2))),
      Byte (Character'Pos (Kind (Kind'First + 3)))];

   function Box (Kind : String; Payload : Byte_Array) return Byte_Array is
     (B32 (Long_Long_Integer (Payload'Length) + 8) & Tag (Kind) & Payload);

   --  The usual table layout: version and flags = 0, count, then entries.
   function Table (Count : Long_Long_Integer; Entries : Byte_Array) return Byte_Array is
     (B32s (0, Count) & Entries);

   function Stsd (Codec : String) return Byte_Array is
     (Box ("stsd", Table (1, Box (Codec, [1 .. 8 => 0]))));

   function Hdlr (Handler : String) return Byte_Array is
     (Box ("hdlr", B32 (0) & Tag ("mhlr") & Tag (Handler) & B32 (0)));

   function Trak (Handler : String; Stbl_Payload : Byte_Array) return Byte_Array is
     (Box ("trak", Box ("tkhd", [1 .. 4 => 0])
           & Box ("mdia", Hdlr (Handler)
                  & Box ("minf", Hdlr ("url ") & Box ("stbl", Stbl_Payload)))));

   function Trak_Stbl
     (Handler, Codec            : String;
      Stts, Stsc, Stsz, Offsets : Byte_Array) return Byte_Array
   is (Trak (Handler, Stsd (Codec) & Stts & Stsc & Stsz & Offsets));

   function Moov (Children : Byte_Array) return Byte_Array is
     (Box ("ftyp", Tag ("qt  ")) & Box ("moov", Children) & Box ("mdat", [1 .. 4 => 7]));

   --  The good tables. Each test replaces one of them with a broken one.
   Good_Stts : constant Byte_Array := Box ("stts", Table (1, B32s (3, 512)));
   Good_Stsc : constant Byte_Array :=
     Box ("stsc", Table (2, B32s (1, 2, 1) & B32s (2, 1, 1)));
   Good_Stsz : constant Byte_Array :=
     Box ("stsz", B32s (0, 0, 3) & B32 (100) & B32 (200) & B32 (300));
   Good_Stco : constant Byte_Array := Box ("stco", Table (2, B32s (1_000, 2_000)));

   Audio_Stts : constant Byte_Array := Box ("stts", Table (1, B32s (1_440_009, 1)));
   Audio_Stsc : constant Byte_Array := Box ("stsc", Table (1, B32s (1, 800, 1)));
   Audio_Stsz : constant Byte_Array := Box ("stsz", B32s (0, 2, 1_440_009));
   Audio_Co64 : constant Byte_Array :=
     Box ("co64", Table (2, B32s (0, 5_000) & B32s (0, 9_000)));

   Video_Trak : constant Byte_Array :=
     Trak_Stbl ("vide", "jpeg", Good_Stts, Good_Stsc, Good_Stsz, Good_Stco);
   Audio_Trak : constant Byte_Array :=
     Trak_Stbl ("soun", "sowt", Audio_Stts, Audio_Stsc, Audio_Stsz, Audio_Co64);

   Good_File : constant Byte_Array :=
     Moov (Box ("mvhd", [1 .. 8 => 0]) & Video_Trak & Audio_Trak & Box ("udta", Nothing));

   --  An exception inside Read_Tables reaches the handlers below, so a
   --  test catches a "raise" as a FAIL and keeps going.
   procedure Accepted (Label_Text : String; Data : Byte_Array) is
   begin
      Read_Tables (Data, Data'Length, T.all, Ok);
      Check (Label_Text, Ok);
   exception
      when E : others =>
         Check (Label_Text & " raised " & Ada.Exceptions.Exception_Name (E), False);
   end Accepted;

   procedure Rejected (Label_Text : String; Data : Byte_Array) is
   begin
      Reject_Size (Label_Text, Data, Data'Length);
   end Rejected;

   procedure Reject_Size (Label_Text : String; Data : Byte_Array; File_Size : Natural) is
   begin
      Read_Tables (Data, File_Size, T.all, Ok);
      Check (Label_Text, not Ok
             and then T.Video.Codec = None and then T.Audio.Codec = None
             and then T.Video.Time_Run_Count = 0 and then T.Video.Chunk_Run_Count = 0
             and then T.Video.Size_Count = 0 and then T.Video.Chunk_Count = 0
             and then T.Audio.Time_Run_Count = 0 and then T.Audio.Chunk_Count = 0);
   exception
      when E : others =>
         Check (Label_Text & " raised " & Ada.Exceptions.Exception_Name (E), False);
   end Reject_Size;

   procedure Test_Good_File is
   begin
      Accepted ("good video and audio file", Good_File);
      if not Ok then
         return;
      end if;

      Check ("video codec", T.Video.Codec = JPEG and then T.Video.Entry_Type = "jpeg");
      Check ("audio codec", T.Audio.Codec = PCM_S16 and then T.Audio.Entry_Type = "sowt");

      Check ("stts stored as one run, not expanded",
             T.Video.Time_Run_Count = 1
             and then T.Video.Time_Runs (1).Sample_Count = 3
             and then T.Video.Time_Runs (1).Sample_Delta = 512);
      Check ("stsc stored as two runs, not expanded",
             T.Video.Chunk_Run_Count = 2
             and then T.Video.Chunk_Runs (1).First_Chunk = 1
             and then T.Video.Chunk_Runs (1).Samples_Per_Chunk = 2
             and then T.Video.Chunk_Runs (2).First_Chunk = 2
             and then T.Video.Chunk_Runs (2).Samples_Per_Chunk = 1);
      Check ("stsz list", T.Video.Uniform_Size = 0 and then T.Video.Sample_Count = 3
             and then T.Video.Size_Count = 3 and then T.Video.Sizes (1) = 100
             and then T.Video.Sizes (2) = 200 and then T.Video.Sizes (3) = 300);
      Check ("stco list", T.Video.Chunk_Count = 2 and then T.Video.Chunk_Offsets (1) = 1_000
             and then T.Video.Chunk_Offsets (2) = 2_000);
      Check ("co64 list", T.Audio.Chunk_Count = 2 and then T.Audio.Chunk_Offsets (1) = 5_000
             and then T.Audio.Chunk_Offsets (2) = 9_000);
   end Test_Good_File;

   procedure Test_Shapes is
      Only_Moov : constant Byte_Array := Box ("moov", Video_Trak);
   begin
      Accepted ("video only", Moov (Video_Trak));
      Check ("video only has no audio", Ok and then T.Audio.Codec = None);
      Accepted ("audio only", Moov (Audio_Trak));
      Check ("audio only has no video", Ok and then T.Video.Codec = None);

      Accepted ("audio track before video track", Moov (Audio_Trak & Video_Trak));
      Check ("track order does not matter", Ok and then T.Video.Codec = JPEG
             and then T.Audio.Codec = PCM_S16);

      Accepted ("timecode track skipped",
                Moov (Trak ("tmcd", Nothing) & Video_Trak));
      Check ("skipped track stores nothing", Ok and then T.Audio.Codec = None);

      Accepted ("moov after mdat", Box ("mdat", [1 .. 9 => 1]) & Box ("moov", Video_Trak));

      Read_Tables (Only_Moov, Only_Moov'Length + 1_000, T.all, Ok);
      Check ("file bigger than Data, moov complete", Ok);

      Accepted ("lpcm audio", Moov (Trak_Stbl ("soun", "lpcm", Audio_Stts, Audio_Stsc,
                                               Audio_Stsz, Audio_Co64)));
      Accepted ("twos audio", Moov (Trak_Stbl ("soun", "twos", Audio_Stts, Audio_Stsc,
                                               Audio_Stsz, Audio_Co64)));

      Accepted ("empty tables", Moov (Trak_Stbl ("vide", "jpeg",
                Box ("stts", Table (0, Nothing)), Box ("stsc", Table (0, Nothing)),
                Box ("stsz", B32s (0, 0, 0)), Box ("stco", Table (0, Nothing)))));

      Accepted ("spare bytes after the entries",
                Moov (Trak_Stbl ("vide", "jpeg", Good_Stts, Good_Stsc, Good_Stsz,
                      Box ("stco", Table (2, B32s (1_000, 2_000) & B32 (0))))));

      --  size = 1: this stsz has the 16-byte header, with the real size
      --  in the 64-bit field after the type.
      Accepted ("table with a 64-bit box header",
                Moov (Trak_Stbl ("vide", "jpeg", Good_Stts, Good_Stsc,
                      B32 (1) & Tag ("stsz") & B32s (0, 32)
                      & B32s (0, 0, 1) & B32 (100), Good_Stco)));
      Check ("64-bit header entries read", Ok and then T.Video.Size_Count = 1
             and then T.Video.Sizes (1) = 100);

      declare
         --  Positions in Data are file positions, even when not 1-based.
         Shifted : constant Byte_Array (50 .. Only_Moov'Length + 49) := Only_Moov;
      begin
         Read_Tables (Shifted, Shifted'Last, T.all, Ok);
         Check ("array not starting at 1", Ok and then T.Video.Size_Count = 3);
      end;
   end Test_Shapes;

   procedure Test_Missing_Boxes is
      S : constant Byte_Array := Stsd ("jpeg");
   begin
      Rejected ("empty input", Nothing);
      declare
         Odd_Bounds : constant Byte_Array (0 .. -1) := [];
      begin
         Rejected ("empty input with First = 0", Odd_Bounds);
      end;
      Reject_Size ("file size zero", Good_File, 0);

      Rejected ("no moov", Box ("ftyp", Tag ("qt  ")) & Box ("mdat", [1 .. 4 => 0]));
      Rejected ("empty moov", Moov (Nothing));
      Rejected ("moov without trak", Moov (Box ("mvhd", [1 .. 8 => 0])));
      Rejected ("only other tracks", Moov (Trak ("tmcd", Nothing)));
      Rejected ("empty trak", Moov (Box ("trak", Nothing)));
      Rejected ("trak without mdia", Moov (Box ("trak", Box ("tkhd", [1 .. 4 => 0]))));
      Rejected ("empty mdia", Moov (Box ("trak", Box ("mdia", Nothing))));
      Rejected ("mdia without hdlr",
                Moov (Box ("trak", Box ("mdia", Box ("minf", Nothing)))));
      --  A good track comes after these, so they fail because of the bad
      --  hdlr itself and not because the file has no usable track.
      Rejected ("hdlr too short",
                Moov (Box ("trak", Box ("mdia", Box ("hdlr", [1 .. 11 => 0])))
                      & Video_Trak));
      Rejected ("empty hdlr",
                Moov (Box ("trak", Box ("mdia", Box ("hdlr", Nothing))) & Video_Trak));
      Rejected ("mdia without minf", Moov (Box ("trak", Box ("mdia", Hdlr ("vide")))));
      Rejected ("empty minf",
                Moov (Box ("trak", Box ("mdia", Hdlr ("vide") & Box ("minf", Nothing)))));
      Rejected ("minf without stbl",
                Moov (Box ("trak", Box ("mdia", Hdlr ("vide")
                                        & Box ("minf", Hdlr ("url "))))));
      Rejected ("empty stbl", Moov (Trak ("vide", Nothing)));

      Rejected ("no stsd", Moov (Trak ("vide", Good_Stts & Good_Stsc & Good_Stsz & Good_Stco)));
      Rejected ("no stts", Moov (Trak ("vide", S & Good_Stsc & Good_Stsz & Good_Stco)));
      Rejected ("no stsc", Moov (Trak ("vide", S & Good_Stts & Good_Stsz & Good_Stco)));
      Rejected ("no stsz", Moov (Trak ("vide", S & Good_Stts & Good_Stsc & Good_Stco)));
      Rejected ("no stco or co64", Moov (Trak ("vide", S & Good_Stts & Good_Stsc & Good_Stsz)));
   end Test_Missing_Boxes;

   procedure Test_Stsd is
      function With_Stsd (Data : Byte_Array) return Byte_Array is
        (Moov (Trak ("vide", Data & Good_Stts & Good_Stsc & Good_Stsz & Good_Stco)));
      Description : constant Byte_Array := Box ("jpeg", [1 .. 8 => 0]);
   begin
      Rejected ("stsd too short", With_Stsd (Box ("stsd", [1 .. 7 => 0])));
      Rejected ("stsd with no entries", With_Stsd (Box ("stsd", Table (0, Nothing))));
      Rejected ("stsd with two entries",
                With_Stsd (Box ("stsd", Table (2, Description & Description))));
      Rejected ("stsd promises an entry it lacks",
                With_Stsd (Box ("stsd", Table (1, Nothing))));
      Rejected ("stsd entry shorter than a header",
                With_Stsd (Box ("stsd", Table (1, [1 .. 7 => 0]))));
      Rejected ("stsd entry reaching past stsd",
                With_Stsd (Box ("stsd", Table (1, B32 (99) & Tag ("jpeg")))));
      Rejected ("video codec we do not read",
                Moov (Trak_Stbl ("vide", "avc1", Good_Stts, Good_Stsc, Good_Stsz, Good_Stco)));
      Rejected ("audio codec we do not read",
                Moov (Trak_Stbl ("soun", "mp4a", Audio_Stts, Audio_Stsc,
                                 Audio_Stsz, Audio_Co64)));
      Rejected ("audio codec on a video track",
                Moov (Trak_Stbl ("vide", "sowt", Good_Stts, Good_Stsc, Good_Stsz, Good_Stco)));
      Rejected ("video codec on an audio track",
                Moov (Trak_Stbl ("soun", "jpeg", Good_Stts, Good_Stsc, Good_Stsz, Good_Stco)));
   end Test_Stsd;

   procedure Test_Bad_Tables is
      function Stts (Data : Byte_Array) return Byte_Array is
        (Moov (Trak_Stbl ("vide", "jpeg", Box ("stts", Data), Good_Stsc, Good_Stsz, Good_Stco)));
      function Stsc (Data : Byte_Array) return Byte_Array is
        (Moov (Trak_Stbl ("vide", "jpeg", Good_Stts, Box ("stsc", Data), Good_Stsz, Good_Stco)));
      function Stsz (Data : Byte_Array) return Byte_Array is
        (Moov (Trak_Stbl ("vide", "jpeg", Good_Stts, Good_Stsc, Box ("stsz", Data), Good_Stco)));
      function Stco (Data : Byte_Array) return Byte_Array is
        (Moov (Trak_Stbl ("vide", "jpeg", Good_Stts, Good_Stsc, Good_Stsz, Box ("stco", Data))));
      function Co64 (Data : Byte_Array) return Byte_Array is
        (Moov (Trak_Stbl ("vide", "jpeg", Good_Stts, Good_Stsc, Good_Stsz, Box ("co64", Data))));
      Over   : constant Long_Long_Integer := Max_Samples + 1;
      Huge   : constant Long_Long_Integer := 2 ** 31 - 1;  --  count * size would overflow
      Top    : constant Long_Long_Integer := 2 ** 32 - 1;
   begin
      --  Too small to hold even the table's own header.
      Rejected ("stts with no payload", Stts (Nothing));
      Rejected ("stts header cut short", Stts ([1 .. 7 => 0]));
      Rejected ("stsc with no payload", Stsc (Nothing));
      Rejected ("stsz header cut short", Stsz ([1 .. 11 => 0]));
      Rejected ("stco with no payload", Stco (Nothing));
      Rejected ("co64 header cut short", Co64 ([1 .. 7 => 0]));

      --  A version or flags field we do not know.
      Rejected ("stts nonzero version", Stts (B32s (16#0100_0000#, 0)));
      Rejected ("stsc nonzero flags", Stsc (B32s (1, 0)));
      Rejected ("stsz nonzero version", Stsz (B32s (16#0100_0000#, 0, 0)));
      Rejected ("stco nonzero flags", Stco (B32s (1, 0)));
      Rejected ("co64 nonzero version", Co64 (B32s (16#0100_0000#, 0)));

      --  The count needs more bytes than the box has.
      Rejected ("stts one entry short", Stts (Table (2, B32s (3, 512))));
      Rejected ("stts partial entry", Stts (Table (1, B32 (3))));
      Rejected ("stsc one entry short", Stsc (Table (2, B32s (1, 2, 1))));
      Rejected ("stsc partial entry", Stsc (Table (1, B32s (1, 2))));
      Rejected ("stsz one entry short", Stsz (B32s (0, 0, 2) & B32 (100)));
      Rejected ("stco one entry short", Stco (Table (2, B32 (1_000))));
      Rejected ("co64 one entry short", Co64 (Table (2, B32s (0, 1_000))));
      Rejected ("co64 partial entry", Co64 (Table (1, B32 (0))));

      --  The count is bigger than Max_Samples, or than the bytes could
      --  ever be, or than Natural itself.
      Rejected ("stts count over Max_Samples", Stts (Table (Over, Nothing)));
      Rejected ("stsc count over Max_Samples", Stsc (Table (Over, Nothing)));
      Rejected ("stsz count over Max_Samples", Stsz (B32s (0, 0, Over)));
      Rejected ("stco count over Max_Samples", Stco (Table (Over, Nothing)));
      Rejected ("co64 count over Max_Samples", Co64 (Table (Over, Nothing)));
      Rejected ("stts count near Natural'Last", Stts (Table (Huge, Nothing)));
      Rejected ("stsc count near Natural'Last", Stsc (Table (Huge, Nothing)));
      Rejected ("stsz count near Natural'Last", Stsz (B32s (0, 0, Huge)));
      Rejected ("co64 count near Natural'Last", Co64 (Table (Huge, Nothing)));
      Rejected ("stts count above Natural", Stts (Table (Top, Nothing)));
      Rejected ("stsz count above Natural", Stsz (B32s (0, 0, Top)));
      Rejected ("stco count above Natural", Stco (Table (Top, Nothing)));

      --  An entry value that does not fit Natural.
      Rejected ("stts run count too large", Stts (Table (1, B32s (Too_Large, 1))));
      Rejected ("stts delta too large", Stts (Table (1, B32s (1, Too_Large))));
      Rejected ("stsc first chunk too large", Stsc (Table (1, B32s (Too_Large, 1, 1))));
      Rejected ("stsc per-chunk too large", Stsc (Table (1, B32s (1, Too_Large, 1))));
      Rejected ("stsz uniform size too large", Stsz (B32s (0, Too_Large, 1)));
      Rejected ("stsz entry too large", Stsz (B32s (0, 0, 1) & B32 (Too_Large)));
      Rejected ("stco offset too large", Stco (Table (1, B32 (Too_Large))));
      Rejected ("co64 high half set", Co64 (Table (1, B32s (1, 0))));
      Rejected ("co64 low half too large", Co64 (Table (1, B32s (0, Too_Large))));

      Rejected ("stsc description index 0", Stsc (Table (1, B32s (1, 2, 0))));
      Rejected ("stsc description index 2", Stsc (Table (1, B32s (1, 2, 2))));
   end Test_Bad_Tables;

   --  The exact edge, with all the bytes really present, so it is the
   --  Max_Samples check that decides and not the "past the box" check.
   procedure Test_Max_Samples is
      generic
         with function Build (Count : Long_Long_Integer) return Byte_Array;
         Label_Text : String;
      procedure Edge;

      procedure Edge is
         At_Limit  : constant Long_Long_Integer := Max_Samples;
      begin
         Accepted (Label_Text & " at Max_Samples", Build (At_Limit));
         Rejected (Label_Text & " over Max_Samples, bytes present", Build (At_Limit + 1));
      end Edge;

      --  Count all-zero bytes, or all-1 U32s for stsc's description field.
      function Zeros (Count : Long_Long_Integer; Size : Positive) return Byte_Array is
        (Byte_Array'[1 .. Natural (Count) * Size => 0]);

      function Stsc_Entries (Count : Long_Long_Integer) return Byte_Array;

      function Stsc_Entries (Count : Long_Long_Integer) return Byte_Array is
         Result : Byte_Array := Zeros (Count, 12);
      begin
         for I in 1 .. Natural (Count) loop
            Result (I * 12) := 1;
         end loop;
         return Result;
      end Stsc_Entries;

      function Big_Stts (Count : Long_Long_Integer) return Byte_Array is
        (Moov (Trak_Stbl ("vide", "jpeg", Box ("stts", Table (Count, Zeros (Count, 8))),
                          Good_Stsc, Good_Stsz, Good_Stco)));
      function Big_Stsc (Count : Long_Long_Integer) return Byte_Array is
        (Moov (Trak_Stbl ("vide", "jpeg", Good_Stts,
                          Box ("stsc", Table (Count, Stsc_Entries (Count))),
                          Good_Stsz, Good_Stco)));
      function Big_Stsz (Count : Long_Long_Integer) return Byte_Array is
        (Moov (Trak_Stbl ("vide", "jpeg", Good_Stts, Good_Stsc,
                          Box ("stsz", B32s (0, 0, Count) & Zeros (Count, 4)), Good_Stco)));
      function Big_Stco (Count : Long_Long_Integer) return Byte_Array is
        (Moov (Trak_Stbl ("vide", "jpeg", Good_Stts, Good_Stsc, Good_Stsz,
                          Box ("stco", Table (Count, Zeros (Count, 4))))));
      function Big_Co64 (Count : Long_Long_Integer) return Byte_Array is
        (Moov (Trak_Stbl ("vide", "jpeg", Good_Stts, Good_Stsc, Good_Stsz,
                          Box ("co64", Table (Count, Zeros (Count, 8))))));

      procedure Edge_Stts is new Edge (Big_Stts, "stts");
      procedure Edge_Stsc is new Edge (Big_Stsc, "stsc");
      procedure Edge_Stsz is new Edge (Big_Stsz, "stsz");
      procedure Edge_Stco is new Edge (Big_Stco, "stco");
      procedure Edge_Co64 is new Edge (Big_Co64, "co64");
   begin
      Edge_Stts;
      Edge_Stsc;
      Edge_Stsz;
      Edge_Stco;
      Edge_Co64;
   end Test_Max_Samples;

   --  The spec's audio rule, and the three cases around it.
   procedure Test_Audio_Rule is
      Over : constant Long_Long_Integer := Max_Samples + 1;
   begin
      Accepted ("audio uniform stsz may exceed Max_Samples", Good_File);
      Check ("audio keeps the count, stores no entries",
             Ok and then T.Audio.Sample_Count = 1_440_009
             and then T.Audio.Uniform_Size = 2 and then T.Audio.Size_Count = 0);

      Rejected ("video uniform stsz over Max_Samples",
                Moov (Trak_Stbl ("vide", "jpeg", Good_Stts, Good_Stsc,
                                 Box ("stsz", B32s (0, 2, Over)), Good_Stco)));
      Rejected ("audio stsz list over Max_Samples",
                Moov (Trak_Stbl ("soun", "sowt", Audio_Stts, Audio_Stsc,
                                 Box ("stsz", B32s (0, 0, Over)), Audio_Co64)));
      Rejected ("audio chunk table over Max_Samples",
                Moov (Trak_Stbl ("soun", "sowt", Audio_Stts, Audio_Stsc, Audio_Stsz,
                                 Box ("stco", Table (Over, Nothing)))));
   end Test_Audio_Rule;

   procedure Test_Tracks is
      Bad_Size : Byte_Array := Video_Trak;
   begin
      Rejected ("two video tracks", Moov (Video_Trak & Video_Trak));
      Rejected ("two audio tracks", Moov (Audio_Trak & Audio_Trak));

      --  A good first track must not hide damage after it.
      Rejected ("junk after the first track", Moov (Video_Trak & [1 .. 3 => 0]));
      Rejected ("box too small after the first track", Moov (Video_Trak & B32s (4, 0)));
      Rejected ("box too large after the first track", Moov (Video_Trak & B32s (999, 0)));
      Rejected ("second track broken",
                Moov (Video_Trak & Trak ("soun", Stsd ("sowt") & Audio_Stts)));

      Bad_Size (Bad_Size'First + 2) := 16#FF#;  --  trak claims 64 KB more
      Rejected ("track reaching past moov", Moov (Bad_Size));

      Accepted ("a good read first", Good_File);
      Rejected ("failure leaves no old results behind", Moov (Nothing));
   end Test_Tracks;

   --  Week 3 step 1: the mdhd timescale, in both versions of the box.
   procedure Test_Timescale is
      Stbl : constant Byte_Array :=
        Stsd ("jpeg") & Good_Stts & Good_Stsc & Good_Stsz & Good_Stco;

      --  A video track whose mdia holds Mdhd in front of the hdlr.
      function With_Mdhd (Mdhd : Byte_Array) return Byte_Array is
        (Moov (Box ("trak", Box ("mdia", Mdhd & Hdlr ("vide")
                                 & Box ("minf", Box ("stbl", Stbl))))));

      --  Version 0: version/flags, creation, modification, timescale,
      --  duration, language and quality. Version 1: the times are 8 bytes.
      V0 : constant Byte_Array :=
        Box ("mdhd", B32s (0, 0, 0) & B32s (15_360, 900) & B32 (0));
      V1 : constant Byte_Array :=
        Box ("mdhd", B32 (16#0100_0000#) & B32s (0, 0, 0) & B32s (0, 48_000, 0)
             & B32s (0, 0));
   begin
      Accepted ("mdhd version 0", With_Mdhd (V0));
      Check ("mdhd version 0 timescale", Ok and then T.Video.Timescale = 15_360);
      Accepted ("mdhd version 1", With_Mdhd (V1));
      Check ("mdhd version 1 timescale", Ok and then T.Video.Timescale = 48_000);
      Accepted ("no mdhd", Good_File);
      Check ("no mdhd leaves timescale 0", Ok and then T.Video.Timescale = 0);
      Accepted ("mdhd timescale 0 is read as 0",
                With_Mdhd (Box ("mdhd", B32s (0, 0, 0) & B32s (0, 900) & B32 (0))));
      Check ("timescale 0 kept for step 4 to reject", Ok and then T.Video.Timescale = 0);

      Rejected ("mdhd version 2", With_Mdhd (Box ("mdhd", B32 (16#0200_0000#)
                                                 & B32s (0, 0, 0) & B32s (0, 0, 0))));
      Rejected ("mdhd empty", With_Mdhd (Box ("mdhd", Nothing)));
      Rejected ("mdhd v0 cut before timescale", With_Mdhd (Box ("mdhd", B32s (0, 0, 0))));
      Rejected ("mdhd v1 cut before timescale",
                With_Mdhd (Box ("mdhd", B32 (16#0100_0000#) & B32s (0, 0, 0) & B32 (0))));
      Rejected ("mdhd timescale too large",
                With_Mdhd (Box ("mdhd", B32s (0, 0, 0) & B32 (Too_Large))));
   end Test_Timescale;

   --  Cut the file at every byte. With either File_Size, nothing is
   --  accepted until the moov is complete. Everything after it is unused.
   procedure Test_Truncation is
      Header : Boxes.Box_Header;
      Found  : Boolean;
   begin
      Boxes.Find_Child (Good_File, 1, Good_File'Last, "moov", Header, Found);
      Check ("test file has a moov", Found);

      for N in 0 .. Header.Box_Last - 1 loop
         Reject_Size ("cut, true file size" & N'Image, Good_File (1 .. N), Good_File'Length);
         Reject_Size ("cut, short file size" & N'Image, Good_File (1 .. N), N);
      end loop;

      for N in Header.Box_Last .. Good_File'Last loop
         Read_Tables (Good_File (1 .. N), N, T.all, Ok);
         Check ("complete moov accepted at" & N'Image, Ok);
      end loop;
   end Test_Truncation;

   --  Replace each byte of the file with each value that tends to cause
   --  trouble. The result may be Ok or not; it must simply never raise.
   --  The Post of Read_Tables is also checked here, on every call.
   procedure Test_Every_Byte_Damaged is
      Values  : constant Byte_Array := [0, 1, 2, 8, 16#7F#, 16#80#, 16#FF#];
      Damaged : Byte_Array := Good_File;
      Calls   : Natural := 0;
      Raised  : Natural := 0;
   begin
      for I in Damaged'Range loop
         for V of Values loop
            Damaged (I) := V;
            begin
               Read_Tables (Damaged, Damaged'Length, T.all, Ok);
            exception
               when others =>
                  Raised := Raised + 1;
            end;
            Calls := Calls + 1;
         end loop;
         Damaged (I) := Good_File (I);
      end loop;
      Check ("damaged bytes never raise:" & Calls'Image & " tries," & Raised'Image & " raised",
             Raised = 0);
   end Test_Every_Byte_Damaged;

   --  Runs against a real proxy. See tests/compare_tables.sh.
   procedure Test_Real_File (Filename : String) is
      use Ada.Streams;

      type Raw_Access is access Stream_Element_Array;
      type Bytes_Access is access Byte_Array;

      procedure Report (Name : String; R : Raw_Track);

      procedure Report (Name : String; R : Raw_Track) is
         Size_Sum : Long_Long_Integer := 0;
      begin
         for I in 1 .. R.Size_Count loop
            Size_Sum := Size_Sum + Long_Long_Integer (R.Sizes (I));
         end loop;
         if R.Codec /= None then
            Put_Line ("COUNTS " & Name & " entry=" & R.Entry_Type
                      & " stts=" & R.Time_Run_Count'Image
                      & " stsc=" & R.Chunk_Run_Count'Image
                      & " samples=" & R.Sample_Count'Image
                      & " uniform=" & R.Uniform_Size'Image
                      & " sizes=" & R.Size_Count'Image
                      & " chunks=" & R.Chunk_Count'Image
                      & " sizesum=" & Size_Sum'Image
                      & " first=" & (if R.Chunk_Count > 0
                                      then R.Chunk_Offsets (1)'Image else " 0"));
         end if;
      end Report;

      File   : Stream_IO.File_Type;
      Raw    : Raw_Access;
      Data   : Bytes_Access;
      Last   : Stream_Element_Offset;
      Header : Boxes.Box_Header;
      Found  : Boolean;
   begin
      Stream_IO.Open (File, Stream_IO.In_File, Filename);
      Raw := new Stream_Element_Array (1 .. Stream_Element_Offset (Stream_IO.Size (File)));
      Stream_IO.Read (File, Raw.all, Last);
      Stream_IO.Close (File);

      Data := new Byte_Array (1 .. Natural (Last));
      for I in Data'Range loop
         Data (I) := Byte (Raw (Stream_Element_Offset (I)));
      end loop;

      Read_Tables (Data.all, Data'Length, T.all, Ok);
      Check ("real file accepted", Ok);
      Report ("video", T.Video);
      Report ("audio", T.Audio);

      --  Ten cuts inside moov. They are all rejected, as a real cut file
      --  must be. The cut points are evenly spread, so a failure repeats.
      Boxes.Find_Child (Data.all, 1, Data'Last, "moov", Header, Found);
      Check ("real file has a moov", Found);
      if Found then
         for K in 1 .. 10 loop
            declare
               Span : constant Natural := Header.Box_Last - Header.Box_First;
               N    : constant Natural := Header.Box_First + Span * K / 11;
            begin
               Reject_Size ("real file cut at" & N'Image, Data (1 .. N), N);
               Reject_Size ("real file cut, true size, at" & N'Image,
                            Data (1 .. N), Data'Length);
            end;
         end loop;
      end if;
   exception
      when E : others =>
         Check ("could not test " & Filename & ": " & Ada.Exceptions.Exception_Name (E), False);
   end Test_Real_File;

begin
   Test_Good_File;
   Test_Shapes;
   Test_Missing_Boxes;
   Test_Stsd;
   Test_Bad_Tables;
   Test_Max_Samples;
   Test_Audio_Rule;
   Test_Tracks;
   Test_Timescale;
   Test_Truncation;
   Test_Every_Byte_Damaged;

   for I in 1 .. Ada.Command_Line.Argument_Count loop
      Test_Real_File (Ada.Command_Line.Argument (I));
   end loop;

   if Failures = 0 then
      Put_Line ("all ISOBMFF table reader tests passed");
   else
      Put_Line (Failures'Image & " table reader test failure(s)");
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;
end Table_Reader_Tests;
