with Framewise.ISOBMFF.Boxes;
with Framewise.ISOBMFF.Resolve;
with Framewise.ISOBMFF.Tables;

package body Framewise.ISOBMFF with SPARK_Mode is

   --  The steps are the ones in the spec header. Most of the work is in
   --  the child packages: Boxes (box headers), Tables (steps 1 to 3) and
   --  Resolve (steps 3 and 4). Parse only joins them up.
   procedure Parse (Header : Byte_Array; File_Size : Natural; M : out File_Map) is
      Raw       : Tables.Raw_Tables;  --  about 3 MB, on the stack (see Tables)
      Mdat      : Boxes.Box_Header;
      Video_End : Time;
      Audio_End : Time;
      Found     : Boolean;
      Good      : Boolean;
   begin
      M := (others => <>);  --  Ok = False, both tracks empty

      --  An empty array can have any bounds, even Header'First = 0.
      if Header'Length = 0 then
         return;
      end if;

      --  Step 2: the tables. This needs all of moov inside Header.
      Tables.Read_Tables (Header, File_Size, Raw, Good);
      if not Good then
         return;
      end if;

      --  Step 1: mdat among the top-level boxes. Only its header has to be
      --  in Header, so a faststart file can be read up to the end of the
      --  mdat header and no further (plan, Option 1). Find_Child also
      --  finds it if it comes before moov, as long as Header holds both.
      Boxes.Find_Child (Header, Header'First, File_Size, "mdat", Mdat, Found);
      if not Found or else Mdat.Payload_Size = 0 then
         return;
      end if;

      --  Box positions start at 1; file offsets (stco, Sample.Offset)
      --  start at 0. Subtract 1 to go from one to the other.
      M.Mdat_First := Mdat.Payload_First - 1;
      M.Mdat_Last := Mdat.Box_Last - 1;

      --  Steps 3 and 4, one track at a time. A failed Resolve_Track
      --  leaves its own track empty.
      Resolve.Resolve_Track (Raw.Video, M.Mdat_First, M.Mdat_Last, M.Video, Video_End, Good);
      if not Good then
         return;
      end if;

      Resolve.Resolve_Track (Raw.Audio, M.Mdat_First, M.Mdat_Last, M.Audio, Audio_End, Good);
      if not Good then
         --  A good video track next to a bad audio track is still a bad
         --  file. Leave nothing behind that looks usable.
         M.Video.Codec := None;
         M.Video.Count := 0;
         return;
      end if;

      M.Length := Time'Max (Video_End, Audio_End);
      M.Ok := True;
   end Parse;

   --  A binary search, like Java's Arrays.binarySearch, but for "the
   --  last sample whose Start <= At_Time". It works because Starts never
   --  go down: each one is the one before plus a duration.
   function Sample_At (T : Track; At_Time : Time) return Sample_Index is
      Low  : Sample_Index;
      High : Sample_Index;
      Mid  : Sample_Index;
   begin
      if T.Count = 0 or else T.Samples (1).Start > At_Time then
         return 0;
      end if;

      --  All the time: sample Low starts at or before At_Time, and every
      --  sample after High starts after it. When Low = High, that's it.
      Low := 1;
      High := T.Count;
      while Low < High loop
         --  Round up, so Mid > Low and Low = Mid always moves forward.
         Mid := Low + (High - Low + 1) / 2;
         if T.Samples (Mid).Start <= At_Time then
            Low := Mid;
         else
            High := Mid - 1;
         end if;
         pragma Loop_Variant (Decreases => High - Low);
      end loop;

      return Low;
   end Sample_At;

end Framewise.ISOBMFF;
