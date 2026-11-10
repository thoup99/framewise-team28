with Framewise.ISOBMFF.Boxes;

package body Framewise.Decode is

   use type Framewise.ISOBMFF.Track_Codec;
   use type Ada.Streams.Stream_IO.Count;
   use type Ada.Streams.Stream_Element_Offset;

   procedure Probe
     (File                    : String;
      Length                  : out Duration_T;
      Kind_Video, Kind_Audio : out Boolean;
      Ok                      : out Boolean)
   is
      H    : Handle;
      Good : Boolean;
   begin
      Length := 0;
      Kind_Video := False;
      Kind_Audio := False;
      Ok := False;

      Open (H, File, Good);

      if not Good then
         return;
      end if;

      Length := H.Map.Length;

      Kind_Video :=
        H.Map.Video.Codec = ISOBMFF.JPEG;

      Kind_Audio :=
        H.Map.Audio.Codec = ISOBMFF.PCM_S16;

      Ok := True;

      Close (H);
   end Probe;

   procedure Open
     (H    : in out Handle;
      File : String;
      Ok   : out Boolean)
   is
      File_Size_Count : Ada.Streams.Stream_IO.Count;
      File_Size       : Natural;
      Position        : Positive := 1;
      Prefix_Last     : Natural := 0;
      Box_Header      : ISOBMFF.Boxes.Box_Header;
      Box_Ok          : Boolean;
      Found_Mdat      : Boolean := False;
   begin
      Close (H);
      Ok := False;

      begin
         Ada.Streams.Stream_IO.Open
           (H.File,
            Ada.Streams.Stream_IO.In_File,
            File);
      exception
         when others =>
            return;
      end;

      File_Size_Count := Ada.Streams.Stream_IO.Size (H.File);

      if File_Size_Count = 0
        or else File_Size_Count >
          Ada.Streams.Stream_IO.Count (Natural'Last)
      then
         Close (H);
         return;
      end if;

      File_Size := Natural (File_Size_Count);

      --  Proxies use +faststart, so moov appears before mdat.
      --  Walk only the top-level box headers until mdat is found.
      while Position <= File_Size loop
         declare
            Header_Bytes : constant Natural :=
              Natural'Min (16, File_Size - Position + 1);

            Raw : Ada.Streams.Stream_Element_Array
              (1 .. Ada.Streams.Stream_Element_Offset (Header_Bytes));

            Last : Ada.Streams.Stream_Element_Offset;

            Header_Data : ISOBMFF.Byte_Array
              (Position .. Position + Header_Bytes - 1);
         begin
            Ada.Streams.Stream_IO.Set_Index
              (H.File,
               Ada.Streams.Stream_IO.Positive_Count (Position));

            Ada.Streams.Stream_IO.Read
              (H.File, Raw, Last);

            if Last /= Raw'Last then
               Close (H);
               return;
            end if;

            for I in Header_Data'Range loop
               Header_Data (I) :=
                 ISOBMFF.Byte
                   (Raw
                      (Ada.Streams.Stream_Element_Offset
                         (I - Position + 1)));
            end loop;

            ISOBMFF.Boxes.Read_Box
              (Header_Data,
               Position,
               File_Size,
               Box_Header,
               Box_Ok);

            if not Box_Ok then
               Close (H);
               return;
            end if;

            if Box_Header.Kind = "mdat" then
               Prefix_Last :=
                 Box_Header.Box_First +
                 Box_Header.Header_Length - 1;

               Found_Mdat := True;
               exit;
            end if;

            exit when Box_Header.Box_Last >= File_Size;

            Position := Box_Header.Box_Last + 1;
         end;
      end loop;

      if not Found_Mdat then
         Close (H);
         return;
      end if;

      --  Parse needs everything from the beginning of the file through
      --  the mdat header. The mdat payload itself does not need loading.
      declare
         Raw : Ada.Streams.Stream_Element_Array
           (1 .. Ada.Streams.Stream_Element_Offset (Prefix_Last));

         Last : Ada.Streams.Stream_Element_Offset;

         Header_Data : ISOBMFF.Byte_Array
           (1 .. Prefix_Last);
      begin
         Ada.Streams.Stream_IO.Set_Index
           (H.File, Ada.Streams.Stream_IO.Positive_Count'First);

         Ada.Streams.Stream_IO.Read
           (H.File, Raw, Last);

         if Last /= Raw'Last then
            Close (H);
            return;
         end if;

         for I in Header_Data'Range loop
            Header_Data (I) :=
              ISOBMFF.Byte
                (Raw (Ada.Streams.Stream_Element_Offset (I)));
         end loop;

         ISOBMFF.Parse
           (Header_Data,
            File_Size,
            H.Map);
      end;

      if not H.Map.Ok then
         Close (H);
         return;
      end if;

      H.Opened := True;
      Ok := True;

   exception
      when others =>
         Close (H);
         Ok := False;
   end Open;

   procedure Close (H : in out Handle) is
   begin
      if Ada.Streams.Stream_IO.Is_Open (H.File) then
         begin
            Ada.Streams.Stream_IO.Close (H.File);
         exception
            when others =>
               null;
         end;
      end if;

      H.Opened := False;
      H.Map := (others => <>);
   end Close;

   procedure Frame_At
     (H : in out Handle; T : Time; Width, Height : Positive;
      Pixels : out RGBA_Buffer; Ok : out Boolean)
   is
      pragma Unreferenced (H, T, Width, Height);
   begin
      Pixels := [others => 0];
      Ok := False;
   end Frame_At;

end Framewise.Decode;