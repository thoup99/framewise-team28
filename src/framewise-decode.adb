with Ada.Unchecked_Deallocation;
with Framewise.ISOBMFF.Boxes;

package body Framewise.Decode is

   use type Framewise.ISOBMFF.Track_Codec;
   use type Framewise.ISOBMFF.Sample_Index;
   use type Ada.Streams.Stream_IO.Count;
   use type Ada.Streams.Stream_Element_Offset;

   procedure Free is new Ada.Unchecked_Deallocation
     (Framewise.JPEG.Byte_Array, JPEG_Buffer_Access);

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

      Free (H.Cached_Pixels);
      H.Cached_Index := 0;
      H.Cached_Header := (others => <>);
      H.Opened := False;
      H.Map := (others => <>);
   end Close;

   procedure Frame_At
   (H : in out Handle; T : Time; Width, Height : Positive;
   Pixels : out RGBA_Buffer; Ok : out Boolean; Preserve_Aspect : Boolean := False)
   is
      Index       : ISOBMFF.Sample_Index;
      Data        : JPEG_Buffer_Access := null;
      Decoded     : JPEG_Buffer_Access := null;
      Header      : Framewise.JPEG.Header;
      Header_Ok   : Boolean;
      Decode_Ok   : Boolean;
      Draw_Width  : Positive := Width;
      Draw_Height : Positive := Height;
      Left, Top   : Natural := 0;
   begin
      Pixels := [others => 0];
      Ok := False;

      if not H.Opened
         or else H.Map.Video.Codec /= ISOBMFF.JPEG
      then
         return;
      end if;

      Index := ISOBMFF.Sample_At (H.Map.Video, T);

      if Index = 0 then
         return;
      end if;

      if H.Cached_Index /= Index or else H.Cached_Pixels = null then
         declare
            S : ISOBMFF.Sample renames H.Map.Video.Samples (Index);
         begin
            if S.Size = 0 then
               return;
            end if;

            Data :=
               new Framewise.JPEG.Byte_Array
                  (1 .. S.Size);

            declare
               Raw : Ada.Streams.Stream_Element_Array
                  (1 .. Ada.Streams.Stream_Element_Offset (S.Size));

               Last : Ada.Streams.Stream_Element_Offset;
            begin
            --  ISOBMFF offsets are zero-based. Stream_IO indices are
            --  one-based, so add one when seeking into the file.
               Ada.Streams.Stream_IO.Set_Index
                  (H.File,
                  Ada.Streams.Stream_IO.Positive_Count
                     (S.Offset + 1));

               Ada.Streams.Stream_IO.Read
                  (H.File, Raw, Last);

               if Last /= Raw'Last then
                  Free (Data);
                  return;
               end if;

               for I in 1 .. S.Size loop
                  Data (I) :=
                     Framewise.JPEG.Byte
                        (Raw
                           (Ada.Streams.Stream_Element_Offset (I)));
               end loop;
            end;
         end;

         Framewise.JPEG.Read_Header
            (Data.all, Header, Header_Ok);

         if not Header_Ok then
            Free (Data);
            return;
         end if;

         Decoded :=
            new Framewise.JPEG.Byte_Array
               (1 .. Header.Width * Header.Height * 4);

         Framewise.JPEG.Decode
            (Data.all,
            Header,
            Decoded.all,
            Decode_Ok);

         Free (Data);

         if not Decode_Ok then
            Free (Decoded);
            return;
         end if;

         --  Publish the new cache only after a complete successful decode.
         Free (H.Cached_Pixels);
         H.Cached_Pixels := Decoded;
         Decoded := null;
         H.Cached_Header := Header;
         H.Cached_Index := Index;
      end if;
      Header := H.Cached_Header;

      if Preserve_Aspect then
         --  Cross products use 64 bits so large output sizes cannot overflow.
         if Long_Long_Integer (Width) * Long_Long_Integer (Header.Height) <=
           Long_Long_Integer (Height) * Long_Long_Integer (Header.Width)
         then
            Draw_Height := Positive
              (Long_Long_Integer'Max (1,
               Long_Long_Integer (Width) * Long_Long_Integer (Header.Height) /
               Long_Long_Integer (Header.Width)));
         else
            Draw_Width := Positive
              (Long_Long_Integer'Max (1,
               Long_Long_Integer (Height) * Long_Long_Integer (Header.Width) /
               Long_Long_Integer (Header.Height)));
         end if;
         Left := (Width - Draw_Width) / 2;
         Top := (Height - Draw_Height) / 2;
      end if;

      --  Fill the canvas with opaque black, including any letterbox bars.
      for I in 0 .. Width * Height - 1 loop
         Pixels (Pixels'First + I * 4 + 3) := 255;
      end loop;

      --  Nearest-neighbour scaling from the cached native frame into the
      --  centered destination rectangle. Failed requests still return zeros.
      for Y in 0 .. Draw_Height - 1 loop
         declare
            Source_Y : constant Natural :=
               Y * Header.Height / Draw_Height;
         begin
            for X in 0 .. Draw_Width - 1 loop
               declare
                  Source_X : constant Natural :=
                     X * Header.Width / Draw_Width;

                  Source_Base : constant Natural :=
                     (Source_Y * Header.Width + Source_X) * 4;

                  Target_Base : constant Natural :=
                     ((Y + Top) * Width + X + Left) * 4;
               begin
                  for Channel in 0 .. 3 loop
                     Pixels
                        (Pixels'First +
                        Target_Base +
                        Channel) :=
                        ISOBMFF.Byte
                           (H.Cached_Pixels
                              (H.Cached_Pixels'First +
                              Source_Base +
                              Channel));
                  end loop;
               end;
            end loop;
         end;
      end loop;

      Free (Decoded);
      Ok := True;

   exception
      when others =>
         Free (Data);
         Free (Decoded);
         Pixels := [others => 0];
         Ok := False;
   end Frame_At;

end Framewise.Decode;