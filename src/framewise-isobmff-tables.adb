package body Framewise.ISOBMFF.Tables with SPARK_Mode is

   use Framewise.ISOBMFF.Boxes;

   --  Most tables start with 4 bytes of version and flags, then a 4-byte
   --  entry count. stsz has one more field, its uniform size, in between.
   Table_Header : constant := 8;
   Stsz_Header  : constant := 12;

   Run_Bytes   : constant := 8;   --  stts entry: 2 U32
   Stsc_Bytes  : constant := 12;  --  stsc entry: 3 U32
   U32_Bytes   : constant := 4;   --  stsz and stco entry: 1 U32
   Co64_Bytes  : constant := 8;   --  co64 entry: 1 U64

   --  True if Count entries are allowed and really fit in Box after its
   --  header bytes. It divides instead of multiplying, because a hostile
   --  Count times Entry_Bytes could overflow.
   function Fits
     (Box          : Box_Header;
      Header_Bytes : Positive;
      Entry_Bytes  : Positive;
      Count        : Natural) return Boolean
   is
     (Count <= Max_Samples
      and then Box.Payload_Size >= Header_Bytes
      and then Count <= (Box.Payload_Size - Header_Bytes) / Entry_Bytes);

   --  Where entry I of a table starts in the file. Only call it for an I
   --  inside a table that passed Fits, so the sum stays inside the box.
   function Entry_Position
     (Box          : Box_Header;
      Header_Bytes : Positive;
      Entry_Bytes  : Positive;
      I            : Sample_Index) return Positive
   is
     (Box.Payload_First + Header_Bytes + Natural (I - 1) * Entry_Bytes);

   procedure Clear (T : in out Raw_Track);

   procedure Find_Inside
     (Data   : Byte_Array;
      Parent : Box_Header;
      Kind   : Box_Kind;
      Child  : out Box_Header;
      Found  : out Boolean);

   procedure Read_Table_Start
     (Data        : Byte_Array;
      Box         : Box_Header;
      Entry_Bytes : Positive;
      Count       : out Sample_Index;
      Ok          : out Boolean);

   procedure Read_Stts
     (Data : Byte_Array; Box : Box_Header; T : in out Raw_Track; Ok : out Boolean);

   procedure Read_Stsc
     (Data : Byte_Array; Box : Box_Header; T : in out Raw_Track; Ok : out Boolean);

   procedure Read_Stsz
     (Data     : Byte_Array;
      Box      : Box_Header;
      Is_Audio : Boolean;
      T        : in out Raw_Track;
      Ok       : out Boolean);

   procedure Read_Stco
     (Data : Byte_Array; Box : Box_Header; T : in out Raw_Track; Ok : out Boolean);

   procedure Read_Co64
     (Data : Byte_Array; Box : Box_Header; T : in out Raw_Track; Ok : out Boolean);

   procedure Read_Entry_Type
     (Data     : Byte_Array;
      Stbl     : Box_Header;
      Is_Audio : Boolean;
      T        : in out Raw_Track;
      Ok       : out Boolean);

   --  "Global => null" says it uses no package-level variables. Any such
   --  contract also stops GNATprove from pasting the body into each
   --  caller for analysis. Here that pasting made it warn about the audio
   --  branch in the video copy; for Read_Trak, inside the moov loop with a
   --  variant, it is not supported at all.
   procedure Read_Stbl
     (Data     : Byte_Array;
      Mdia     : Box_Header;
      Is_Audio : Boolean;
      T        : in out Raw_Track;
      Ok       : out Boolean)
     with Global => null;

   procedure Read_Trak
     (Data   : Byte_Array;
      Trak   : Box_Header;
      Tables : in out Raw_Tables;
      Ok     : out Boolean)
     with Global => null;

   --  Only the counts need resetting: they say which entries are valid.
   --  Assigning a default Raw_Track could build 1.5 MB on the stack.
   procedure Clear (T : in out Raw_Track) is
   begin
      T.Codec := None;
      T.Entry_Type := "    ";
      T.Time_Run_Count := 0;
      T.Chunk_Run_Count := 0;
      T.Sample_Count := 0;
      T.Uniform_Size := 0;
      T.Size_Count := 0;
      T.Chunk_Count := 0;
   end Clear;

   --  An empty box has Payload_First = 0, which Find_Child's Positive
   --  First cannot accept, so that case has to stop here.
   procedure Find_Inside
     (Data   : Byte_Array;
      Parent : Box_Header;
      Kind   : Box_Kind;
      Child  : out Box_Header;
      Found  : out Boolean)
   is
   begin
      if Parent.Payload_Size = 0 then
         Child := (others => <>);
         Found := False;
      else
         Find_Child (Data, Parent.Payload_First, Parent.Box_Last, Kind, Child, Found);
      end if;
   end Find_Inside;

   --  Reads the header shared by stts, stsc, stco and co64.
   procedure Read_Table_Start
     (Data        : Byte_Array;
      Box         : Box_Header;
      Entry_Bytes : Positive;
      Count       : out Sample_Index;
      Ok          : out Boolean)
   is
      Version_Flags : Natural;
      Raw_Count     : Natural;
      Good          : Boolean;
   begin
      Count := 0;
      Ok := False;

      if Box.Payload_Size < Table_Header then
         return;
      end if;

      Read_U32 (Data, Box.Payload_First, Version_Flags, Good);
      if not Good or else Version_Flags /= 0 then
         return;
      end if;

      Read_U32 (Data, Box.Payload_First + 4, Raw_Count, Good);
      if not Good or else not Fits (Box, Table_Header, Entry_Bytes, Raw_Count) then
         return;
      end if;

      Count := Sample_Index (Raw_Count);
      Ok := True;
   end Read_Table_Start;

   procedure Read_Stts
     (Data : Byte_Array; Box : Box_Header; T : in out Raw_Track; Ok : out Boolean)
   is
      Count    : Sample_Index;
      Position : Positive;
   begin
      Read_Table_Start (Data, Box, Run_Bytes, Count, Ok);
      if not Ok then
         return;
      end if;

      for I in 1 .. Count loop
         Position := Entry_Position (Box, Table_Header, Run_Bytes, I);
         Read_U32 (Data, Position, T.Time_Runs (I).Sample_Count, Ok);
         if Ok then
            Read_U32 (Data, Position + 4, T.Time_Runs (I).Sample_Delta, Ok);
         end if;
         if not Ok then
            return;
         end if;
      end loop;

      T.Time_Run_Count := Count;
   end Read_Stts;

   procedure Read_Stsc
     (Data : Byte_Array; Box : Box_Header; T : in out Raw_Track; Ok : out Boolean)
   is
      Count       : Sample_Index;
      Position    : Positive;
      Description : Natural;
   begin
      Read_Table_Start (Data, Box, Stsc_Bytes, Count, Ok);
      if not Ok then
         return;
      end if;

      for I in 1 .. Count loop
         Position := Entry_Position (Box, Table_Header, Stsc_Bytes, I);
         Read_U32 (Data, Position, T.Chunk_Runs (I).First_Chunk, Ok);
         if Ok then
            Read_U32 (Data, Position + 4, T.Chunk_Runs (I).Samples_Per_Chunk, Ok);
         end if;
         if Ok then
            Read_U32 (Data, Position + 8, Description, Ok);
            Ok := Ok and then Description = 1;
         end if;
         if not Ok then
            return;
         end if;
      end loop;

      T.Chunk_Run_Count := Count;
   end Read_Stsc;

   --  stsz is the one table whose layout changes. With a nonzero uniform
   --  size there are no entries at all, just the count.
   procedure Read_Stsz
     (Data     : Byte_Array;
      Box      : Box_Header;
      Is_Audio : Boolean;
      T        : in out Raw_Track;
      Ok       : out Boolean)
   is
      Version_Flags : Natural;
      Uniform       : Natural;
      Raw_Count     : Natural;
      Good          : Boolean;
   begin
      Ok := False;

      if Box.Payload_Size < Stsz_Header then
         return;
      end if;

      Read_U32 (Data, Box.Payload_First, Version_Flags, Good);
      if not Good or else Version_Flags /= 0 then
         return;
      end if;

      Read_U32 (Data, Box.Payload_First + 4, Uniform, Good);
      if not Good then
         return;
      end if;

      Read_U32 (Data, Box.Payload_First + 8, Raw_Count, Good);
      if not Good then
         return;
      end if;

      if Uniform /= 0 then
         --  The audio rule in the spec header. Video makes one Sample per
         --  frame in step 4, so its count must fit even with no entries.
         if not Is_Audio and then Raw_Count > Max_Samples then
            return;
         end if;

      else
         if not Fits (Box, Stsz_Header, U32_Bytes, Raw_Count) then
            return;
         end if;

         for I in 1 .. Sample_Index (Raw_Count) loop
            Read_U32 (Data, Entry_Position (Box, Stsz_Header, U32_Bytes, I),
                      T.Sizes (I), Good);
            if not Good then
               return;
            end if;
         end loop;

         T.Size_Count := Sample_Index (Raw_Count);
      end if;

      T.Uniform_Size := Uniform;
      T.Sample_Count := Raw_Count;
      Ok := True;
   end Read_Stsz;

   procedure Read_Stco
     (Data : Byte_Array; Box : Box_Header; T : in out Raw_Track; Ok : out Boolean)
   is
      Count : Sample_Index;
   begin
      Read_Table_Start (Data, Box, U32_Bytes, Count, Ok);
      if not Ok then
         return;
      end if;

      for I in 1 .. Count loop
         Read_U32 (Data, Entry_Position (Box, Table_Header, U32_Bytes, I),
                   T.Chunk_Offsets (I), Ok);
         if not Ok then
            return;
         end if;
      end loop;

      T.Chunk_Count := Count;
   end Read_Stco;

   --  A co64 offset is 8 bytes. We read it as two U32 halves: all offsets
   --  in this project are Natural, so the high half has to be 0, and the
   --  low half must pass Read_U32's own Natural check.
   procedure Read_Co64
     (Data : Byte_Array; Box : Box_Header; T : in out Raw_Track; Ok : out Boolean)
   is
      Count    : Sample_Index;
      Position : Positive;
      High     : Natural;
   begin
      Read_Table_Start (Data, Box, Co64_Bytes, Count, Ok);
      if not Ok then
         return;
      end if;

      for I in 1 .. Count loop
         Position := Entry_Position (Box, Table_Header, Co64_Bytes, I);
         Read_U32 (Data, Position, High, Ok);
         if Ok and then High = 0 then
            Read_U32 (Data, Position + 4, T.Chunk_Offsets (I), Ok);
         else
            Ok := False;
         end if;
         if not Ok then
            return;
         end if;
      end loop;

      T.Chunk_Count := Count;
   end Read_Co64;

   --  stsd: 4 bytes of version and flags, a 4-byte entry count, then the
   --  entries. Each entry is shaped like a box whose type is the codec, so
   --  Read_Box reads it and also proves it stays inside stsd.
   procedure Read_Entry_Type
     (Data     : Byte_Array;
      Stbl     : Box_Header;
      Is_Audio : Boolean;
      T        : in out Raw_Track;
      Ok       : out Boolean)
   is
      Stsd        : Box_Header;
      Description : Box_Header;
      Count       : Natural;
      Found       : Boolean;
      Good        : Boolean;
   begin
      Ok := False;

      Find_Inside (Data, Stbl, "stsd", Stsd, Found);
      if not Found or else Stsd.Payload_Size < Table_Header then
         return;
      end if;

      Read_U32 (Data, Stsd.Payload_First + 4, Count, Good);
      if not Good or else Count /= 1 then
         return;
      end if;

      --  It promised one entry but has no bytes left for it. Read_Box would
      --  refuse that too; checking here keeps the "+ Table_Header" below
      --  from pointing past the box, which a later proof will need.
      if Stsd.Payload_Size = Table_Header then
         return;
      end if;

      Read_Box (Data, Stsd.Payload_First + Table_Header, Stsd.Box_Last, Description, Good);
      if not Good then
         return;
      end if;

      if Is_Audio then
         if Description.Kind = "sowt"
           or else Description.Kind = "lpcm"
           or else Description.Kind = "twos"
         then
            T.Codec := PCM_S16;
         end if;
      elsif Description.Kind = "jpeg" then
         T.Codec := JPEG;
      end if;

      if T.Codec /= None then
         T.Entry_Type := Description.Kind;
         Ok := True;
      end if;
   end Read_Entry_Type;

   procedure Read_Stbl
     (Data     : Byte_Array;
      Mdia     : Box_Header;
      Is_Audio : Boolean;
      T        : in out Raw_Track;
      Ok       : out Boolean)
   is
      Minf  : Box_Header;
      Stbl  : Box_Header;
      Table : Box_Header;
      Found : Boolean;
   begin
      Ok := False;

      Find_Inside (Data, Mdia, "minf", Minf, Found);
      if not Found then
         return;
      end if;
      Find_Inside (Data, Minf, "stbl", Stbl, Found);
      if not Found then
         return;
      end if;

      Read_Entry_Type (Data, Stbl, Is_Audio, T, Ok);
      if not Ok then
         return;
      end if;

      Find_Inside (Data, Stbl, "stts", Table, Found);
      if not Found then
         Ok := False;
         return;
      end if;
      Read_Stts (Data, Table, T, Ok);
      if not Ok then
         return;
      end if;

      Find_Inside (Data, Stbl, "stsc", Table, Found);
      if not Found then
         Ok := False;
         return;
      end if;
      Read_Stsc (Data, Table, T, Ok);
      if not Ok then
         return;
      end if;

      Find_Inside (Data, Stbl, "stsz", Table, Found);
      if not Found then
         Ok := False;
         return;
      end if;
      Read_Stsz (Data, Table, Is_Audio, T, Ok);
      if not Ok then
         return;
      end if;

      --  A file uses one or the other: try the 32-bit table first.
      Find_Inside (Data, Stbl, "stco", Table, Found);
      if Found then
         Read_Stco (Data, Table, T, Ok);
         return;
      end if;

      Find_Inside (Data, Stbl, "co64", Table, Found);
      if Found then
         Read_Co64 (Data, Table, T, Ok);
      else
         Ok := False;
      end if;
   end Read_Stbl;

   --  hdlr: 4 bytes of version and flags, 4 bytes of component type, then
   --  the 4 bytes we want. Only mdia's hdlr names the media; minf has its
   --  own hdlr about data references, which Find_Inside never looks at.
   procedure Read_Trak
     (Data   : Byte_Array;
      Trak   : Box_Header;
      Tables : in out Raw_Tables;
      Ok     : out Boolean)
   is
      Mdia    : Box_Header;
      Hdlr    : Box_Header;
      Handler : Box_Kind;  --  the loop below fills all 4 characters
      Found   : Boolean;
   begin
      Ok := False;

      Find_Inside (Data, Trak, "mdia", Mdia, Found);
      if not Found then
         return;
      end if;

      Find_Inside (Data, Mdia, "hdlr", Hdlr, Found);
      if not Found or else Hdlr.Payload_Size < 12 then
         return;
      end if;

      for I in Handler'Range loop
         Handler (I) := Character'Val (Natural (Data (Hdlr.Payload_First + 7 + I)));
      end loop;

      if Handler = "vide" then
         if Tables.Video.Codec = None then
            Read_Stbl (Data, Mdia, False, Tables.Video, Ok);
         end if;
      elsif Handler = "soun" then
         if Tables.Audio.Codec = None then
            Read_Stbl (Data, Mdia, True, Tables.Audio, Ok);
         end if;
      else
         Ok := True;  --  some other track, such as timecode: not for us
      end if;
   end Read_Trak;

   procedure Read_Tables
     (Data      : Byte_Array;
      File_Size : Natural;
      Tables    : in out Raw_Tables;
      Ok        : out Boolean)
   is
      Moov     : Box_Header;
      Child    : Box_Header;
      Position : Positive;
      Found    : Boolean;
      Good     : Boolean;
   begin
      Clear (Tables.Video);
      Clear (Tables.Audio);
      Ok := False;

      --  An empty array can have any bounds, even Data'First = 0.
      if Data'Length = 0 then
         return;
      end if;

      Find_Child (Data, Data'First, File_Size, "moov", Moov, Found);
      if not Found or else Moov.Payload_Size = 0 then
         return;
      end if;

      --  From here on every box is inside moov, so inside Data as well.
      if Moov.Box_Last > Data'Last then
         return;
      end if;

      --  This walk uses Read_Box, not Find_Child, on purpose. Find_Child
      --  cannot tell "no more traks" from "a corrupt box", and a corrupt
      --  box here would silently lose the rest of the tracks.
      Position := Moov.Payload_First;
      loop
         Read_Box (Data, Position, Moov.Box_Last, Child, Good);
         if Good and then Child.Kind = "trak" then
            Read_Trak (Data, Child, Tables, Good);
         end if;
         if not Good then
            Clear (Tables.Video);
            Clear (Tables.Audio);
            return;
         end if;

         exit when Child.Box_Last >= Moov.Box_Last;
         Position := Child.Box_Last + 1;
         pragma Loop_Variant (Increases => Position);
      end loop;

      Ok := Tables.Video.Codec /= None or else Tables.Audio.Codec /= None;
   end Read_Tables;

end Framewise.ISOBMFF.Tables;
