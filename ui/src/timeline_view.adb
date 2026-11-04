with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Adi.Core; use Adi.Core;
with Adi.Widget; use Adi.Widget;
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
                        Add_Item (W, Make_Panel (Indicator_Part,
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
                           W.Drag_Name :=
                             To_Unbounded_String (Framewise.Image (C.N));
                           W.Drag_Start_X := X;
                           W.Drag_Start_Time :=
                             Framewise.Seconds (C.Start);
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

      New_Time := Long_Float'Max
        (0.0, W.Drag_Start_Time +
         Long_Float (X - W.Drag_Start_X) / W.Zoom);

      --  Keep conversion to timeline ticks within the valid range.
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
   end On_Mouse_Up;

end Timeline_View;
