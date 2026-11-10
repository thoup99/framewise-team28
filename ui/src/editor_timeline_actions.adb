with Ada.Characters.Latin_1;
with Adi.Core; use Adi.Core;
with Adi.CSS_Styles; use Adi.CSS_Styles;
with Adi.Widget_Styles; use Adi.Widget_Styles;
with Adi.Window; use Adi.Window;
with Framewise;
with Timeline_View;
with Editor_Styles; use Editor_Styles;
with Editor_Dialogs; use Editor_Dialogs;
with Editor_Controller; use Editor_Controller;

package body Editor_Timeline_Actions is
   use type Buttons.Button_Handle;
   use type Labels.Label_Handle;
   use type Inputs.Text_Input_Handle;
   use type Combos.Combo_Box_Handle;
   use type Timeline_View.Views.Handle;
   use type US.Unbounded_String;
   use type Framewise.Time;

   --  The menu remembers only a name, then resolves it against the live session.
   Clip_Menu_Target : US.Unbounded_String;

   procedure Snap_Interval_Changed (Input : Widget_Handle; Text : String) is
      pragma Unreferenced (Input);
      Interval : Framewise.Time := 0;
      Valid : Boolean;
   begin
      declare
         Seconds : Long_Float;
      begin
         Seconds := Long_Float'Value (Text);
         if Seconds in 1.0 / Long_Float (Framewise.Timebase) ..
           Framewise.Seconds (Framewise.Time'Last / 2)
         then
            Interval := Framewise.Time (Seconds * Long_Float (Framewise.Timebase));
         end if;
      exception
         when Constraint_Error => null;
      end;
      Valid := Interval in 1 .. Framewise.Time'Last / 2;
      if Valid then
         declare
            V : Timeline_View.Views.Ref := Timeline_View.Views.Borrow (Tracks);
         begin
            V.Snap_Interval := Interval;
            Mark_Dirty (+Tracks);
         end;
         Tell ("Control-drag snap interval: " & FS.Image_Time (Interval) & " s.");
      else
         Tell ("Enter positive snap seconds (minimum 1/90000 s); the last valid interval is still active.");
      end if;
      declare
         Text_Color : constant Color_Value :=
           (if Valid then RGB (215, 225, 239) else RGB (255, 150, 150));
      begin
         Set_Part_Style (+Snap_Interval_Input, Text_Part, Style.Base
           ((Text_Style with delta Color => Set (Text_Color))).Build);
      end;
   end Snap_Interval_Changed;

   procedure Cursor_Time_Changed (Input : Widget_Handle; Text : String) is
      pragma Unreferenced (Input);
      Value : Long_Float;
      Valid : Boolean := False;
   begin
      if Get_Focus_Handle (W) /= Widget_Handle'(+Cursor_Time_Input) then
         return;
      end if;
      begin
         Value := Long_Float'Value (Text);
         Valid := Value in 0.0 .. Framewise.Seconds (Framewise.Time'Last / 2);
      exception
         when Constraint_Error => null;
      end;
      Set_Part_Style (+Cursor_Time_Input, Main_Part, Style.Base
        ((Width => Set (Size (Px (110.0))), Flex_Shrink => Set (0.0),
          Background_Color => Set_Bg ((if Valid then RGB (38, 50, 67) else RGB (91, 39, 45))),
          Padding => Set (CSS_Box (Px (6.0))), others => <>)).Build);
      if Valid then
         declare
            V : Timeline_View.Views.Ref := Timeline_View.Views.Borrow (Tracks);
            Span : constant Long_Float := Long_Float'Max
              (1.0, Long_Float (Get_Geometry (+Tracks).Width - 110.0) / V.Zoom);
         begin
            if Value < V.First_Second or else Value > V.First_Second + Span then
               V.First_Second := Long_Float'Max (0.0, Value - Span / 2.0);
            end if;
            Timeline_View.Set_Playhead
              (V.Ptr.all, Framewise.Time (Value * Long_Float (Framewise.Timebase)));
         end;
      end if;
   end Cursor_Time_Changed;

   procedure Show_Preview (Text : String) is
   begin
      if Get_Focus_Handle (W) /= Widget_Handle'(+Cursor_Time_Input) then
         declare
            V : Timeline_View.Views.Ref := Timeline_View.Views.Borrow (Tracks);
         begin
            Inputs.Set_Text (Cursor_Time_Input, FS.Image_Time (V.Playhead));
         end;
      end if;
      Labels.Set_Text (Preview, Text & Ada.Characters.Latin_1.LF &
        "Video frame preview is not available yet.");
   end Show_Preview;

   procedure Reset_View is
      V : Timeline_View.Views.Ref := Timeline_View.Views.Borrow (Tracks);
   begin
      Current_Filter := All_Media;
      Update_Filter_Buttons;
      V.Selected_Clip := US.Null_Unbounded_String;
      --  Reset all view state before Refresh_Timeline publishes the new project.
      V.Playhead := 0;
      V.First_Second := 0.0;
      V.Razor_Mode := False;
      Set_Selected (+Razor_Button, False);
      Timeline_View.Set_Razor_Pointer (V.Ptr.all, 0.0, 0.0, False);
      V.Drag_Active := False;
      V.Scrubbing := False;
      Labels.Set_Text (Tool_Status, "");
      Set_Visible (+Tool_Status, False);
   end Reset_View;

   procedure Clip_Selected (Name : String) is
   begin
      Set_Focus (W, +Tracks);
      Tell ((if Name'Length = 0 then "No clip selected."
             else "Selected: " & Name & ". Drag to move, drag an edge to trim, or use Move / Delete."));
   end Clip_Selected;

   procedure Delete_Selected is
      Name : US.Unbounded_String;
   begin
      declare
         V : Timeline_View.Views.Ref := Timeline_View.Views.Borrow (Tracks);
      begin
         Name := V.Selected_Clip;
      end;
      if US.Length (Name) = 0 then
         Report_Editor_Error ("Delete Clip", "Select a timeline clip first.");
         return;
      end if;
      Execute_Line ("delete " & US.To_String (Name));
   end Delete_Selected;

   procedure Show_Clip_Menu (Widget : Widget_Handle; X, Y : Pixel_Type) is
      V : Timeline_View.Views.Ref := Timeline_View.Views.Borrow (Tracks);
      Local : constant Rectangle := Get_Geometry (Widget);
      Visible : constant Rectangle := Geometry_In_Window (Widget);
      --  Context-menu events arrive in window coordinates. Account for the
      --  timeline's scroll offset before looking up the clip under the mouse.
      Name : constant String := Timeline_View.Clip_At
        (V.Ptr.all, X + Local.X - Visible.X, Y + Local.Y - Visible.Y);
   begin
      Menus.Hide (Clip_Menu);
      Clip_Menu_Target := US.To_Unbounded_String (Name);
      if Name = "" then
         return;
      end if;
      --  Rebuilding clears a previous action's retained menu highlight.
      Menus.Clear_Items (Clip_Menu);
      Menus.Add_Item (Clip_Menu, "Snap Timeline Cursor Left");
      Menus.Add_Item (Clip_Menu, "Snap Timeline Cursor Right");
      Menus.Show_At (Clip_Menu, X, Y, 250.0);
   end Show_Clip_Menu;

   procedure Clip_Menu_Selected (Menu : Menus.Menu_Handle; Index : Positive; Text : String) is
      pragma Unreferenced (Menu, Text);
      Seq : constant FS.Sequence_View := Read_Sequence;
      V : Timeline_View.Views.Ref := Timeline_View.Views.Borrow (Tracks);
   begin
      --  Resolve the named clip again in case the document changed while the
      --  menu was open. Cursor navigation does not create an edit or log entry.
      for Track of Seq.Tracks loop
         if Track.Used then
            for I in 1 .. Track.Count loop
               declare
                  C renames Track.Clips (I);
               begin
                  if Framewise.Image (C.N) = US.To_String (Clip_Menu_Target) then
                     Timeline_View.Set_Playhead
                       (V.Ptr.all, C.Start + (if Index = 2 then C.Src_Out - C.Src_In else 0));
                     return;
                  end if;
               end;
            end loop;
         end if;
      end loop;
   end Clip_Menu_Selected;

   procedure Clicked (Button : Widget_Handle) is
   begin
      if Button = Widget_Handle'(+Undo_Button) then
         Execute_Line ("undo");
      elsif Button = Widget_Handle'(+Delete_Button) then
         Delete_Selected;
      elsif Button = Widget_Handle'(+Add_Track_Button) then
         Form_Target := US.To_Unbounded_String (Unique_Name ("track"));
         Prepare_Form (Add_Track, "Add Track - name and media type");
         Set_Field (1, "Track name (letters, numbers, underscores)", US.To_String (Form_Target));
         Dialogs.Show (Form);
         Set_Focus (W, +Values (1));
      elsif Button = Widget_Handle'(+Place_Button) then
         if Combos.Get_Selected_Index (Source_Choice) = 0 or else Combos.Get_Selected_Index (Track_Choice) = 0 then
            Report_Editor_Error ("Add Selected Media to Track",
              "Import a media file and add a track before adding a clip.");
            return;
         end if;
         Form_Target := US.To_Unbounded_String (Unique_Name ("clip"));
         Prepare_Form (Place_Clip, "Add selected media to selected track");
         Set_Field (1, "Source in (seconds)", "0");
         for S of FS.Sequence_Of (Editor).Sources loop
            if S.Used and then Framewise.Image (S.N) = Combos.Get_Selected_Text (Source_Choice) then
               Set_Field (2, "Source out (seconds)", FS.Image_Time (S.Length));
            end if;
         end loop;
         declare
            V : Timeline_View.Views.Ref := Timeline_View.Views.Borrow (Tracks);
         begin
            Set_Field (3, "Timeline start (seconds)", FS.Image_Time (V.Playhead));
         end;
         Dialogs.Show (Form);
      elsif Button = Widget_Handle'(+Move_Button) then
         declare
            V : Timeline_View.Views.Ref := Timeline_View.Views.Borrow (Tracks);
         begin
            Form_Target := V.Selected_Clip;
         end;
         for T of FS.Sequence_Of (Editor).Tracks loop
            for I in 1 .. T.Count loop
               if T.Used and then Framewise.Image (T.Clips (I).N) = US.To_String (Form_Target) then
                  Prepare_Form (Move_Clip, "Move selected clip");
                  Set_Field (1, "Timeline start (seconds)", FS.Image_Time (T.Clips (I).Start));
                  Dialogs.Show (Form);
                  return;
               end if;
            end loop;
         end loop;
         Report_Editor_Error ("Move Clip", "Select a timeline clip first.");
      else
         declare
            V : Timeline_View.Views.Ref := Timeline_View.Views.Borrow (Tracks);
         begin
            if Button = Widget_Handle'(+Razor_Button) then
               V.Razor_Mode := not V.Razor_Mode;
               Set_Selected (+Razor_Button, V.Razor_Mode);
               Mark_Dirty (+Tracks);
               Labels.Set_Text (Tool_Status,
                 (if V.Razor_Mode then "Razor: click inside a clip to split"
                  else ""));
               Set_Visible (+Tool_Status, V.Razor_Mode);
            elsif Button = Widget_Handle'(+Zoom_In) then
               V.Zoom := Long_Float'Min (256.0, V.Zoom * 2.0);
            elsif Button = Widget_Handle'(+Zoom_Out) then
               V.Zoom := Long_Float'Max (8.0, V.Zoom / 2.0);
            elsif Button = Widget_Handle'(+Scroll_Left) then
               V.First_Second := Long_Float'Max (0.0, V.First_Second - 5.0);
            elsif Button = Widget_Handle'(+Scroll_Right) then
               V.First_Second := Long_Float'Min
                 (Framewise.Seconds (Framewise.Time'Last / 2), V.First_Second + 5.0);
            elsif Button = Widget_Handle'(+Start_Button) then
               V.First_Second := 0.0;
               Timeline_View.Set_Playhead (V.Ptr.all, 0);
            elsif Button = Widget_Handle'(+End_Button) then
               declare
                  Last_Frame : Framewise.Time := 0;
               begin
                  for T of Read_Sequence.Tracks loop
                     if T.Used then
                        for I in 1 .. T.Count loop
                           Last_Frame := Framewise.Time'Max (Last_Frame,
                             T.Clips (I).Start + T.Clips (I).Src_Out - T.Clips (I).Src_In);
                        end loop;
                     end if;
                  end loop;

                  V.First_Second := Long_Float'Max (0.0, Framewise.Seconds (Last_Frame) - 5.0);
                  Timeline_View.Set_Playhead (V.Ptr.all, Last_Frame);
               end;
            end if;
            Mark_Dirty (+Tracks);
         end;
      end if;
   end Clicked;
end Editor_Timeline_Actions;
