with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Interfaces.C;
with System;
with System.Storage_Elements; use System.Storage_Elements;
with Adi.SDL.Pixelformat;
with Adi.SDL.Surface;
with Framewise.Decode;

package body Timeline_Thumbnails is
   use type Framewise.Time;
   use type Adi.SDL.Surface.SDL_Surface_Ptr;

   type Cache_Entry is record
      Used, Pending : Boolean := False;
      Source, File : Unbounded_String;
      At_Time : Framewise.Time := 0;
      Image : Adi.Image.Image_Owner;
      Last_Use : Natural := 0;
   end record;
   --  About 4.5 MiB of RGBA data at capacity. Failed requests are cached too.
   Cache : array (1 .. 512) of Cache_Entry;
   Clock : Natural := 0;
   Decoder : Framewise.Decode.Handle;

   procedure Clear is
   begin
      Framewise.Decode.Close (Decoder);
      for E of Cache loop
         Adi.Image.Release (E.Image);
         E := (others => <>);
      end loop;
      Clock := 0;
   end Clear;

   function Request (Source, File : String; At_Time : Framewise.Time)
      return Adi.Image.Image_Handle
   is
      Slot : Positive := Cache'First;
   begin
      --  Avoid counter wrap even during a very long editing session.
      if Clock = Natural'Last then
         for E of Cache loop
            E.Last_Use := 0;
         end loop;
         Clock := 0;
      end if;
      Clock := Clock + 1;
      for I in Cache'Range loop
         if Cache (I).Used and then To_String (Cache (I).Source) = Source
           and then To_String (Cache (I).File) = File
           and then Cache (I).At_Time = At_Time
         then
            Cache (I).Last_Use := Clock;
            return Adi.Image.To_Handle (Cache (I).Image);
         end if;
         if not Cache (I).Used then
            Slot := I;
         elsif Cache (Slot).Used and then Cache (I).Last_Use < Cache (Slot).Last_Use then
            Slot := I;
         end if;
      end loop;
      Adi.Image.Release (Cache (Slot).Image);
      Cache (Slot) :=
        (Used => True, Pending => True,
         Source => To_Unbounded_String (Source), File => To_Unbounded_String (File),
         At_Time => At_Time, Image => Adi.Image.Null_Image_Owner, Last_Use => Clock);
      return Adi.Image.Null_Image_Handle;
   end Request;

   function Process_One return Boolean is
      function C_Memcpy
        (Destination, Source : System.Address; Count : Interfaces.C.size_t)
         return System.Address
        with Import, Convention => C, External_Name => "memcpy";
      Pixels : Framewise.Decode.RGBA_Buffer (1 .. Width * Height * 4);
      Surface : Adi.SDL.Surface.SDL_Surface_Ptr := null;
      Good : Boolean;
   begin
      for E of Cache loop
         if E.Used and then E.Pending then
            E.Pending := False;
            Framewise.Decode.Open (Decoder, To_String (E.File) & ".proxy.mov", Good);
            if Good then
               Framewise.Decode.Frame_At
                 (Decoder, E.At_Time, Width, Height, Pixels, Good, Preserve_Aspect => True);
            end if;
            Framewise.Decode.Close (Decoder);
            if Good then
               Surface := Adi.SDL.Surface.SDL_CreateSurface
                 (Interfaces.C.int (Width), Interfaces.C.int (Height),
                  Adi.SDL.Pixelformat.SDL_PIXELFORMAT_RGBA32);
               if Surface /= null then
                  for Y in 0 .. Height - 1 loop
                     declare
                        Result : constant System.Address := C_Memcpy
                          (Surface.pixels + Storage_Offset (Y * Natural (Surface.pitch)),
                           Pixels (1 + Y * Width * 4)'Address, Interfaces.C.size_t (Width * 4));
                        pragma Unreferenced (Result);
                     begin
                        null;
                     end;
                  end loop;
                  E.Image := Adi.Image.Create_From_Surface (Surface);
                  if not Adi.Image.Is_Owned (E.Image) then
                     Adi.SDL.Surface.SDL_DestroySurface (Surface);
                  end if;
                  Surface := null;
               end if;
            end if;
            return True;
         end if;
      end loop;
      return False;
   exception
      when others =>
         Framewise.Decode.Close (Decoder);
         if Surface /= null then
            Adi.SDL.Surface.SDL_DestroySurface (Surface);
         end if;
         --  Missing/unsupported proxies leave the normal clip panel and label.
         return True;
   end Process_One;
end Timeline_Thumbnails;
