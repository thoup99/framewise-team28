with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Adi.Core; use Adi.Core;
with Adi.Widget; use Adi.Widget;
with Ada.Strings.Fixed;
with Framewise;

package body Timeline_View is
   use type Framewise.Time;
   Gutter : constant Pixel_Type := 110.0;
   Ruler_Height : constant Pixel_Type := 30.0;

   use type Adi.SDL.Events.SDL_Keymod;
   Snap_Distance : constant Long_Float := 10.0;  --  Screen pixels, independent of zoom.

   procedure Update_Drag_Modifiers
     (W : in out Track_Widget; Modifiers : Adi.SDL.Events.SDL_Keymod)
   is
   begin
      if W.Drag_Modifiers /= Modifiers then
         W.Drag_Modifiers := Modifiers;
         if W.Drag_Active then
            Mark_Dirty (W);
         end if;
      end if;
   end Update_Drag_Modifiers;

   --  Preview and release share the same target calculation. Shift aligns
   --  either edge to a valid neighbor on this track; Control rounds the start.
   function Drag_Position (W : Track_Widget; X : Pixel_Type) return Long_Float is
      Raw : constant Long_Float := Long_Float'Max
        (0.0, W.Drag_Start_Time + Long_Float (X - W.Drag_Start_X) / W.Zoom);
      Shift : constant Boolean := (W.Drag_Modifiers and Adi.SDL.Events.SDL_KMOD_SHIFT) /= 0;
      Control : constant Boolean := (W.Drag_Modifiers and Adi.SDL.Events.SDL_KMOD_CTRL) /= 0;
   begin
      if Shift and then W.Read_Sequence /= null then
         declare
            Seq : constant Framewise.Session.Sequence_View := W.Read_Sequence.all;
         begin
            for Track of Seq.Tracks loop
               if Track.Used then
                  declare
                     Found : Boolean := False;
                     Duration : Framewise.Time := 0;
                     Snapped : Boolean := False;
                     Best : Framewise.Time := 0;
                     Best_Distance : Long_Float := Snap_Distance;

                     procedure Consider (Target : Framewise.Time) is
                        Distance : constant Long_Float := abs (Framewise.Seconds (Target) - Raw) * W.Zoom;
                     begin
                        if Distance > Snap_Distance or else
                          (Snapped and then Distance >= Best_Distance) or else
                          Target > Framewise.Time'Last - Duration
                        then
                           return;
                        end if;
                        --  Do not attract a clip into another clip in a crowded gap.
                        --  Use ticks here so touching edges are compared exactly.
                        for I in 1 .. Track.Count loop
                           declare
                              Other renames Track.Clips (I);
                           begin
                              if Framewise.Image (Other.N) /= To_String (W.Drag_Name) and then
                                Target < Other.Start + (Other.Src_Out - Other.Src_In) and then
                                Other.Start < Target + Duration
                              then
                                 return;
                              end if;
                           end;
                        end loop;
                        Snapped := True;
                        Best := Target;
                        Best_Distance := Distance;
                     end Consider;
                  begin
                     for I in 1 .. Track.Count loop
                        if Framewise.Image (Track.Clips (I).N) = To_String (W.Drag_Name) then
                           Found := True;
                           Duration := Track.Clips (I).Src_Out - Track.Clips (I).Src_In;
                           exit;
                        end if;
                     end loop;
                     if Found then
                        for I in 1 .. Track.Count loop
                           declare
                              Other renames Track.Clips (I);
                           begin
                              if Framewise.Image (Other.N) /= To_String (W.Drag_Name) then
                                 Consider (Other.Start + (Other.Src_Out - Other.Src_In));
                                 if Other.Start >= Duration then
                                    Consider (Other.Start - Duration);
                                 end if;
                              end if;
                           end;
                        end loop;
                        if Snapped then
                           return Framewise.Seconds (Best);
                        end if;
                        exit;
                     end if;
                  end;
               end if;
            end loop;
         end;
      end if;
      if Control and then W.Snap_Interval > 0 and then
        W.Snap_Interval <= Framewise.Time'Last / 2 and then
        Raw <= Framewise.Seconds (Framewise.Time'Last / 2)
      then
         --  Round in ticks so decimal intervals and halfway values stay exact.
         declare
            Ticks : constant Framewise.Time := Framewise.Time (Raw * Long_Float (Framewise.Timebase));
            Remainder : constant Framewise.Time := Ticks mod W.Snap_Interval;
            Rounded : Framewise.Time := Ticks - Remainder;
         begin
            if Remainder >= W.Snap_Interval - Remainder then
               Rounded := Rounded + W.Snap_Interval;
            end if;
            return Framewise.Seconds (Rounded);
         end;
      end if;
      return Raw;
   end Drag_Position;

   procedure Set_Razor_Pointer (W : in out Track_Widget;
      X, Y : Pixel_Type; Active : Boolean) is
      Show : constant Boolean := Active and then W.Razor_Mode;
   begin
      if W.Razor_Hover /= Show or else
        (Show and then (W.Razor_X /= X or else W.Razor_Y /= Y))
      then
         W.Razor_Hover := Show;
         W.Razor_X := X;
         W.Razor_Y := Y;
         Mark_Dirty (W);
      end if;
   end Set_Razor_Pointer;

   function Cursor_At (W : Track_Widget; X, Y : Pixel_Type)
      return Adi.SDL.Mouse.SDL_SystemCursor
   is
      use Adi.SDL.Mouse;
      G : constant Rectangle := Get_Geometry (W);
      Left : constant Pixel_Type := G.X + Gutter;
      Right : constant Pixel_Type := G.X + G.Width;
      Row : Pixel_Type := G.Y + Ruler_Height;
   begin
      if W.Scrubbing then
         return SDL_SYSTEM_CURSOR_EW_RESIZE;
      elsif W.Drag_Active then
         return (if W.Drag_Trim_Left or W.Drag_Trim_Right
                 then SDL_SYSTEM_CURSOR_EW_RESIZE else SDL_SYSTEM_CURSOR_MOVE);
      end if;
      if W.Read_Sequence = null or else X < Left or else X > Right
        or else Y < G.Y or else Y > G.Y + G.Height
      then
         return SDL_SYSTEM_CURSOR_DEFAULT;
      end if;
      if Y < Row then
         return SDL_SYSTEM_CURSOR_EW_RESIZE;
      end if;
      for T of W.Read_Sequence.all.Tracks loop
         if T.Used then
            if Y >= Row + 4.0 and then Y <= Row + 40.0 then
               for I in 1 .. T.Count loop
                  declare
                     C renames T.Clips (I);
                     X1 : constant Pixel_Type := Left + Pixel_Type
                       ((Framewise.Seconds (C.Start) - W.First_Second) * W.Zoom);
                     X2 : constant Pixel_Type := X1 + Pixel_Type
                       (Framewise.Seconds (C.Src_Out - C.Src_In) * W.Zoom);
                  begin
                     if X >= Pixel_Type'Max (Left, X1) and then X <= Pixel_Type'Min (Right, X2) then
                        if W.Razor_Mode then
                           return SDL_SYSTEM_CURSOR_DEFAULT;
                        elsif (X1 >= Left and then X <= X1 + 8.0) or else
                          (X2 <= Right and then X >= X2 - 8.0)
                        then
                           return SDL_SYSTEM_CURSOR_EW_RESIZE;
                        end if;
                        return SDL_SYSTEM_CURSOR_MOVE;
                     end if;
                  end;
               end loop;
            end if;
            Row := Row + 48.0;
         end if;
      end loop;
      return SDL_SYSTEM_CURSOR_DEFAULT;
   end Cursor_At;

   function Preview_Text
     (Seq : Framewise.Session.Sequence_View; At_Time : Framewise.Time) return String
   is
      use all type Framewise.Session.Media_Kind;
      Stamp : constant String := Framewise.Session.Image_Time (At_Time) & " s";
   begin
      for Track of Seq.Tracks loop
         --  Export uses the first populated video-capable track.
         if Track.Used and then Natural (Track.Count) > 0 and then Track.Kind /= Audio then
            for I in 1 .. Track.Count loop
               declare
                  C renames Track.Clips (I);
               begin
                  if At_Time >= C.Start and then At_Time - C.Start < C.Src_Out - C.Src_In then
                     return Framewise.Image (C.N) & " | " & Stamp;
                  end if;
               end;
            end loop;
            exit;
         end if;
      end loop;
      return "No video clip | " & Stamp;
   end Preview_Text;

   procedure Scrub_To (W : in out Track_Widget; X : Pixel_Type) is
      G : constant Rectangle := Get_Geometry (W);
      Offset : constant Pixel_Type :=
        Pixel_Type'Max (0.0, Pixel_Type'Min (X - G.X, G.Width) - Gutter);
   begin
      W.Playhead := Framewise.Time
        (Long_Float'Min (Long_Float (Framewise.Time'Last),
         (W.First_Second + Long_Float (Offset) / W.Zoom) * Long_Float (Framewise.Timebase)));
      if W.Preview_Changed /= null then
         W.Preview_Changed.all (Preview_Text (W.Read_Sequence.all, W.Playhead));
      end if;
      Mark_Dirty (W);
   end Scrub_To;

   overriding procedure Build_Items (W : in out Track_Widget) is
      use type Framewise.Time;
      G : constant Rectangle := Get_Geometry (W);
      Left : constant Pixel_Type := G.X + Gutter;
      Right : constant Pixel_Type := G.X + G.Width;
      Y : Pixel_Type := G.Y + Ruler_Height;
      Ghost_Visible : Boolean := False;
      Ghost_Area : Rectangle;
      Ghost_Name : Unbounded_String;

      procedure Label (Area : Rectangle; Text : String; Z_Order : Natural := 2) is
         I : Item := Make_Text (Label_Part, Area, Text, Z_Order);
      begin
         I.Wrap_Text := False;
         Add_Item (W, I);
      end Label;
   begin
      Clear_Items (W);
      Add_Item (W, Make_Panel (Main_Part, G, 0));
      if W.Read_Sequence = null or else G.Width <= Gutter then
         return;
      end if;
      declare
         Seq : constant Framewise.Session.Sequence_View := W.Read_Sequence.all;
         Step : constant Long_Float :=
           (if W.Zoom >= 80.0 then 1.0 elsif W.Zoom >= 24.0 then 5.0 else 10.0);
         T : Long_Float := Long_Float'Ceiling (W.First_Second / Step) * Step;
         X : Pixel_Type;
         Any_Track : Boolean := False;
      begin
         Label ((G.X + 8.0, G.Y + 4.0, 100.0, 24.0), "Track / s");
         loop
            X := Left + Pixel_Type ((T - W.First_Second) * W.Zoom);
            exit when X >= Right;
            Label ((X, G.Y + 4.0, 70.0, 24.0),
                   Framewise.Session.Image_Time
                     (Framewise.Time (T * Long_Float (Framewise.Timebase))));
            T := T + Step;
         end loop;
         for Track of Seq.Tracks loop
            if Track.Used then
               Any_Track := True;
               Add_Item (W, Make_Panel (Custom_Part,
                 (G.X, Y + 1.0, G.Width, 44.0), 0));
               --  Keep the media type below the name so it remains readable
               --  in the fixed track header without changing clip geometry.
               Label ((G.X + 8.0, Y + 3.0, 100.0, 20.0), Framewise.Image (Track.N));
               Label ((G.X + 8.0, Y + 24.0, 100.0, 18.0),
                 (if Track.Kind'Image = "VIDEO" then "Video"
                  elsif Track.Kind'Image = "AUDIO" then "Audio"
                  else "Video + Audio"));
               for I in 1 .. Track.Count loop
                  declare
                     C renames Track.Clips (I);
                     X1 : constant Long_Float :=
                       (Framewise.Seconds (C.Start) - W.First_Second) * W.Zoom;
                     X2 : constant Long_Float := X1 +
                       Framewise.Seconds (C.Src_Out - C.Src_In) * W.Zoom;
                     Visible_Left : constant Pixel_Type :=
                       Left + Pixel_Type (Long_Float'Max (0.0, X1));
                     Visible_Right : constant Pixel_Type :=
                       Left + Pixel_Type (Long_Float'Min (Long_Float (Right - Left), X2));
                  begin
                     if Visible_Right > Visible_Left
                        and then not
                           (W.Drag_Active
                           and then To_String (W.Drag_Name) = Framewise.Image (C.N))
                     then
                        Add_Item (W, Make_Panel
                           ((if To_String (W.Selected_Clip) = Framewise.Image (C.N)
                           then Selected_Part
                           else  Indicator_Part),
                           (Visible_Left, Y + 4.0,
                           Visible_Right - Visible_Left, 36.0), 1));

                        Label ((Visible_Left + 3.0, Y + 10.0,
                              Pixel_Type'Max
                                 (0.0, Visible_Right - Visible_Left - 6.0),
                                 24.0),
                                 Framewise.Image (C.N));                     
                     end if;
                  --  Use the same timeline-to-ticks mapping as the click
                  --  handler; only show cuts strictly inside the clip.
                  if W.Razor_Mode and then W.Razor_Hover and then
                    W.Razor_Y >= Y + 4.0 and then W.Razor_Y <= Y + 40.0
                    and then W.Razor_X >= Visible_Left
                    and then W.Razor_X < Visible_Right and then W.Zoom > 0.0
                  then
                     declare
                        Seconds : constant Long_Float := W.First_Second +
                          Long_Float (W.Razor_X - Left) / W.Zoom;
                     begin
                        if Seconds >= 0.0 and then Seconds <
                          Framewise.Seconds (Framewise.Time'Last / 2)
                        then
                           declare
                              Cut : constant Framewise.Time := Framewise.Time
                                (Seconds * Long_Float (Framewise.Timebase));
                           begin
                              if Cut > C.Start and then Cut - C.Start < C.Src_Out - C.Src_In then
                                 Add_Item (W, Make_Panel (Cursor_Part,
                                   (W.Razor_X, Y + 4.0,
                                    Pixel_Type'Min (2.0, Visible_Right - W.Razor_X), 36.0), 5));
                              end if;
                           end;
                        end if;
                     end;
                  end if;
                  -- Show a temporary ghost while moving or trimming a clip.
                  -- This is only visual UI state. The real timeline is not changed
                  -- until On_Mouse_Up sends the move command.
                  if W.Drag_Active
                     and then To_String (W.Drag_Name) = Framewise.Image (C.N)
                  then
                     declare
                        Delta_Seconds : constant Long_Float :=
                           Long_Float
                              (W.Drag_Current_X - W.Drag_Start_X) / W.Zoom;
                        
                        Preview_Start : Long_Float := W.Drag_Start_Time;
                        Preview_In    : Long_Float := W.Drag_Src_In;
                        Preview_Out   : Long_Float := W.Drag_Src_Out;
                     begin
                        if W.Drag_Trim_Left then
                           Preview_In :=
                              W.Drag_Src_In + Delta_Seconds;
                        
                        elsif W.Drag_Trim_Right then
                           Preview_Out :=
                              W.Drag_Src_Out + Delta_Seconds;

                        else
                           Preview_Start := Drag_Position (W, W.Drag_Current_X);
                        end if;

                        if Preview_In >= 0.0
                           and then Preview_Out > Preview_In
                        then
                           declare
                              Preview_X1 : constant Long_Float :=
                                 (Preview_Start - W.First_Second) * W.Zoom;

                              Preview_X2 : constant Long_Float :=
                                 Preview_X1 +
                                 (Preview_Out - Preview_In) * W.Zoom;

                              Ghost_Left : constant Pixel_Type :=
                                 Left +
                                 Pixel_Type
                                    (Long_Float'Max (0.0, Preview_X1));

                              Ghost_Right : constant Pixel_Type :=
                                 Left +
                                 Pixel_Type
                                    (Long_Float'Min
                                       (Long_Float (Right - Left), Preview_X2));
                           begin
                              if Ghost_Right > Ghost_Left then
                                 Ghost_Visible := True;
                                 Ghost_Area := (Ghost_Left, Y + 4.0, Ghost_Right - Ghost_Left, 36.0);
                                 Ghost_Name := To_Unbounded_String (Framewise.Image (C.N));
                              end if;
                           end;
                  end if;      
                  end;
            end if;
            end;
               end loop;
               Y := Y + 48.0;
            end if;
         end loop;
         --  Adi paints items in insertion order, so defer the dragged clip
         --  until every other clip (including its text) has been added.
         if Ghost_Visible then
            Add_Item (W, Make_Panel (Selected_Part, Ghost_Area, 3));
            Label ((Ghost_Area.X + 3.0, Ghost_Area.Y + 6.0,
              Pixel_Type'Max (0.0, Ghost_Area.Width - 6.0), 24.0), To_String (Ghost_Name), 4);
         end if;
         X := Left + Pixel_Type ((Framewise.Seconds (W.Playhead) - W.First_Second) * W.Zoom);
         if X >= Left and then X < Right then
            Add_Item (W, Make_Panel (Selected_Part,
              (X, G.Y, Pixel_Type'Min (2.0, Right - X), G.Height), 5));
         end if;
         if not Any_Track then
            Label ((Left, Y, Right - Left, 30.0), "No tracks. Use Add Track to begin.");
         end if;
      end;
   end Build_Items;

   overriding procedure On_Mouse_Down
     (W      : in out Track_Widget;
      X, Y   : Pixel_Type;
      Button : Mouse_Button;
      Clicks : Natural := 1)
   is
      pragma Unreferenced (Clicks);
      G     : constant Rectangle := Get_Geometry (W);
      Left  : constant Pixel_Type := G.X + Gutter;
      Right : constant Pixel_Type := G.X + G.Width;
      Row_Y : Pixel_Type := G.Y + Ruler_Height;
   begin

      if Button /= Left_Button then
         return;
      end if;
      W.Scrubbing := False;
      W.Drag_Active := False;
      W.Drag_Trim_Left := False;
      W.Drag_Trim_Right := False;
      Update_Drag_Modifiers (W, Adi.SDL.Events.SDL_GetModState);
      if W.Read_Sequence = null or else W.Zoom <= 0.0 or else X < Left or else X > Right then
         return;
      end if;
      if Y >= G.Y and then Y < Row_Y then
         W.Scrubbing := True;
         Scrub_To (W, X);
         return;
      end if;

      if not W.Razor_Mode then
         W.Selected_Clip := Null_Unbounded_String;
         if W.Selection_Changed /= null then
            W.Selection_Changed.all ("");
         end if;
      end if;

      declare
         Seq : constant Framewise.Session.Sequence_View :=
           W.Read_Sequence.all;
      begin
         for Track of Seq.Tracks loop
            if Track.Used then
               if Y >= Row_Y + 4.0 and then Y <= Row_Y + 40.0 then
                  for I in 1 .. Track.Count loop
                     declare
                        C renames Track.Clips (I);
                        Clip_X1 : constant Pixel_Type :=
                          Left + Pixel_Type
                            ((Framewise.Seconds (C.Start) -
                              W.First_Second) * W.Zoom);
                        Clip_X2 : constant Pixel_Type :=
                          Clip_X1 + Pixel_Type
                            (Framewise.Seconds (C.Src_Out - C.Src_In)
                             * W.Zoom);
                     begin
                        if X >= Pixel_Type'Max (Left, Clip_X1)
                          and then X <= Pixel_Type'Min (Right, Clip_X2)
                        then
   if not W.Razor_Mode then
      W.Selected_Clip :=
         To_Unbounded_String (Framewise.Image (C.N));

      if W.Selection_Changed /= null then
         W.Selection_Changed.all (Framewise.Image (C.N));
      end if;
   end if;
   --  In Razor Mode, a click splits the clip instead of dragging it.
   if W.Razor_Mode then
      if W.Submit_Command /= null then
         declare
            Cut_Seconds : constant Long_Float :=
              W.First_Second + Long_Float (X - Left) / W.Zoom;
         begin
            if Cut_Seconds >= 0.0
              and then Cut_Seconds <
                Long_Float (Framewise.Time'Last / 2) /
                Long_Float (Framewise.Timebase)
            then
               declare
                  Cut : constant Framewise.Time :=
                    Framewise.Time
                      (Cut_Seconds * Long_Float (Framewise.Timebase));
               begin
                  --  The cut must be strictly inside the clip.
                  if Cut > C.Start
                    and then Cut - C.Start < C.Src_Out - C.Src_In
                  then
                     --  Find an unused name for the right-hand clip.
                     for N in 1 .. 9999 loop
                        declare
                           New_Name : constant String :=
                             "r" & Ada.Strings.Fixed.Trim
                               (Positive'Image (N), Ada.Strings.Left);
                           Taken : Boolean := False;
                        begin
                           for Other_Track of Seq.Tracks loop
                              if Other_Track.Used then
                                 for J in 1 .. Other_Track.Count loop
                                    if Framewise.Image
                                      (Other_Track.Clips (J).N) = New_Name
                                    then
                                       Taken := True;
                                       exit;
                                    end if;
                                 end loop;
                              end if;
                              exit when Taken;
                           end loop;

                           if not Taken then
                              W.Submit_Command.all
                                ("split " & Framewise.Image (C.N) & " " &
                                 Framewise.Session.Image_Time (Cut) &
                                 " " & New_Name);
                              return;
                           end if;
                        end;
                     end loop;
                  end if;
               end;
            end if;
         end;
      end if;
      return;
   end if;

                           W.Drag_Name :=
                             To_Unbounded_String (Framewise.Image (C.N));
                           W.Drag_Start_X := X;
                           W.Drag_Current_X := X;
                           W.Drag_Start_Time := Framewise.Seconds (C.Start);
                           W.Drag_Src_In := Framewise.Seconds (C.Src_In);
                           W.Drag_Src_Out := Framewise.Seconds (C.Src_Out);

                        -- First/last 8 pixels act as trim handles.
                        -- A clipped-off edge is not treated as a handle.
                        W.Drag_Trim_Left :=
                           Clip_X1 >= Left and then X <= Clip_X1 + 8.0;

                        W.Drag_Trim_Right :=
                           not W.Drag_Trim_Left
                           and then Clip_X2 <= Right
                           and then X >= Clip_X2 - 8.0;

                        W.Drag_Active := True;
                           return;
                        end if;
                     end;
                  end loop;
               end if;
               Row_Y := Row_Y + 48.0;
            end if;
         end loop;
      end;
   end On_Mouse_Down;

   overriding procedure On_Mouse_Move
      (W   : in out Track_widget;
      X, Y : Pixel_Type)
   is
   begin
      Set_Razor_Pointer (W, X, Y, True);
      if W.Scrubbing then
         Scrub_To (W, X);
      elsif W.Drag_Active then
         Update_Drag_Modifiers (W, Adi.SDL.Events.SDL_GetModState);
         W.Drag_Current_X := X;
         Mark_Dirty (W);
      end if;
   end On_Mouse_Move;

   overriding procedure On_Mouse_Up
     (W      : in out Track_Widget;
      X, Y   : Pixel_Type;
      Button : Mouse_Button)
   is
      pragma Unreferenced (Y);
      New_Time : Long_Float;
   begin
      if Button = Left_Button and then W.Scrubbing then
         W.Scrubbing := False;
         Scrub_To (W, X);
         return;
      end if;
      if Button /= Left_Button or else not W.Drag_Active then
         return;
      end if;
      
      Update_Drag_Modifiers (W, Adi.SDL.Events.SDL_GetModState);
      W.Drag_Current_X := X;
      W.Drag_Active := False;
      Mark_Dirty(W);

      --  Ignore clicks without meaningful mouse movement.
      if abs (X - W.Drag_Start_X) < 3.0
        or else W.Submit_Command = null
        or else W.Zoom <= 0.0
      then
         return;
      end if;

      if W.Drag_Trim_Left then
         -- Dragging the left edge changes the source in-point.
         New_Time :=
            W.Drag_Src_In +
            Long_Float (X - W.Drag_Start_X) / W.Zoom;

         if New_Time < 0.0
            or else New_Time >= W.Drag_Src_Out
         then
            return;
         end if;

         W.Submit_Command.all
            ("trim " & To_String (W.Drag_Name) & " " &
            Framewise.Session.Image_Time
               (Framewise.Time
                  (New_Time * Long_Float (Framewise.Timebase))) &
            " " &
            Framewise.Session.Image_Time
               (Framewise.Time
                  (W.Drag_Src_Out * Long_Float (Framewise.Timebase))));

      elsif W.Drag_Trim_Right then
         --  Dragging the right edge changes the source out-point.
         New_Time :=
           W.Drag_Src_Out +
           Long_Float (X - W.Drag_Start_X) / W.Zoom;

         if New_Time <= W.Drag_Src_In
           or else New_Time >
             Long_Float (Framewise.Time'Last / 2) /
             Long_Float (Framewise.Timebase)
         then
            return;
         end if;

         W.Submit_Command.all
           ("trim " & To_String (W.Drag_Name) & " " &
            Framewise.Session.Image_Time
              (Framewise.Time
                 (W.Drag_Src_In * Long_Float (Framewise.Timebase))) &
            " " &
            Framewise.Session.Image_Time
              (Framewise.Time
                 (New_Time * Long_Float (Framewise.Timebase))));
      else
         --  Dragging the body still moves the entire clip.
         New_Time := Drag_Position (W, X);

         if New_Time >
           Long_Float (Framewise.Time'Last / 2) /
           Long_Float (Framewise.Timebase)
         then
            return;
         end if;

         W.Submit_Command.all
           ("move " & To_String (W.Drag_Name) & " " &
            Framewise.Session.Image_Time
              (Framewise.Time
                 (New_Time * Long_Float (Framewise.Timebase))));
      end if;

   end On_Mouse_Up;

   overriding procedure On_Key_Down
     (W : in out Track_Widget; Scancode : Adi.SDL.Events.SDL_Scancode;
      Key_Mod : Adi.SDL.Events.SDL_Keymod; Repeat : Boolean)
   is
      pragma Unreferenced (Scancode, Repeat);
   begin
      Update_Drag_Modifiers (W, Key_Mod);
   end On_Key_Down;

   overriding procedure On_Key_Up
     (W : in out Track_Widget; Scancode : Adi.SDL.Events.SDL_Scancode;
      Key_Mod : Adi.SDL.Events.SDL_Keymod; Repeat : Boolean)
   is
      pragma Unreferenced (Scancode, Repeat);
   begin
      Update_Drag_Modifiers (W, Key_Mod);
   end On_Key_Up;

end Timeline_View;
