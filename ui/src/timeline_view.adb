with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Adi.Core; use Adi.Core;
with Adi.Widget; use Adi.Widget;
with Ada.Strings.Fixed;
with Framewise;

package body Timeline_View is
   use type Framewise.Time;
   overriding procedure Build_Items (W : in out Track_Widget) is
      use type Framewise.Time;
      G : constant Rectangle := Get_Geometry (W);
      Left : constant Pixel_Type := G.X + 110.0;
      Right : constant Pixel_Type := G.X + G.Width;
      Y : Pixel_Type := G.Y + 30.0;

      procedure Label (Area : Rectangle; Text : String) is
         I : Item := Make_Text (Label_Part, Area, Text, 2);
      begin
         I.Wrap_Text := False;
         Add_Item (W, I);
      end Label;
   begin
      Clear_Items (W);
      Add_Item (W, Make_Panel (Main_Part, G, 0));
      if W.Read_Sequence = null or else G.Width <= 110.0 then
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
               Label ((G.X + 8.0, Y + 8.0, 100.0, 28.0), Framewise.Image (Track.N));
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
                     if Visible_Right > Visible_Left then
                        Add_Item (W, Make_Panel
                           ((if To_String (W.Selected_Clip) = Framewise.Image (C.N)
                           then Selected_Part
                           else Indicator_Part),
                          (Visible_Left, Y + 4.0, Visible_Right - Visible_Left, 36.0), 1));
                        Label ((Visible_Left + 3.0, Y + 10.0,
                                Pixel_Type'Max (0.0, Visible_Right - Visible_Left - 6.0),
                                24.0), Framewise.Image (C.N));
                     end if;
                  end;
               end loop;
               Y := Y + 48.0;
            end if;
         end loop;
         if not Any_Track then
            Label ((Left, Y, Right - Left, 30.0), "No tracks. Load a project below.");
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
      Left  : constant Pixel_Type := G.X + 110.0;
      Right : constant Pixel_Type := G.X + G.Width;
      Row_Y : Pixel_Type := G.Y + 30.0;
   begin

   W.Drag_Active := False;
   W.Drag_Trim_Right := False;

   if not W.Razor_Mode then
      W.Selected_Clip := Null_Unbounded_String;

      if W.Selection_Changed /= null then
         W.Selection_Changed.all ("");
      end if;
   end if;

      if Button /= Left_Button
        or else W.Read_Sequence = null
        or else W.Zoom <= 0.0
        or else X < Left
        or else X > Right
      then
         return;
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
                           W.Drag_Start_Time := Framewise.Seconds (C.Start);
                           W.Drag_Src_In := Framewise.Seconds (C.Src_In);
                           W.Drag_Src_Out := Framewise.Seconds (C.Src_Out);

                        --  The last 8 pixels of the visible clip are the trim handle.
                        --  Do not treat a clipped-off right edge as a trim handle.
                           W.Drag_Trim_Right :=
                              Clip_X2 <= Right and then X >= Clip_X2 - 8.0;

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

   overriding procedure On_Mouse_Up
     (W      : in out Track_Widget;
      X, Y   : Pixel_Type;
      Button : Mouse_Button)
   is
      pragma Unreferenced (Y);
      New_Time : Long_Float;
   begin
      if Button /= Left_Button or else not W.Drag_Active then
         return;
      end if;

      W.Drag_Active := False;

      --  Ignore clicks without meaningful mouse movement.
      if abs (X - W.Drag_Start_X) < 3.0
        or else W.Submit_Command = null
        or else W.Zoom <= 0.0
      then
         return;
      end if;

      if W.Drag_Trim_Right then
         --  Convert horizontal movement into a source out-point.
         --  Keep the existing source in-point and timeline start.
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
         New_Time := Long_Float'Max
           (0.0, W.Drag_Start_Time +
            Long_Float (X - W.Drag_Start_X) / W.Zoom);

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

end Timeline_View;
