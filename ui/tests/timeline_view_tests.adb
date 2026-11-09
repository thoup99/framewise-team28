with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Text_IO;
with Adi.Core; use Adi.Core;
with Adi.Widget; use Adi.Widget;
with Framewise.Session;
with Timeline_View;
with Adi.SDL.Mouse;
with Adi.SDL.Events;
with Framewise;

procedure Timeline_View_Tests is
   package FS renames Framewise.Session;
   S : FS.Session;
   R : FS.Response;
   H : Timeline_View.Views.Handle := Timeline_View.Views.New_Widget;
   use type Timeline_View.Views.Handle;
   use type Adi.SDL.Mouse.SDL_SystemCursor;
   use type Adi.SDL.Events.SDL_Keymod;
   use type Framewise.Time;

   --  Exercise the native modifier state used by the real drag handlers.
   procedure Set_Modifiers (Modifiers : Adi.SDL.Events.SDL_Keymod)
     with Import, Convention => C, External_Name => "SDL_SetModState";
   function Read_Sequence return FS.Sequence_View is (FS.Sequence_Of (S));

   procedure Run (Line : String; Success : Boolean := True) is
   begin
      FS.Execute (S, Line, R);
      pragma Assert (R.Ok = Success, FS.Image (R));
   end Run;

   Last_Preview : Unbounded_String;
   Expect_Mouse_Success : Boolean := True;

   procedure Record_Preview (Text : String) is
   begin
      Last_Preview := To_Unbounded_String (Text);
   end Record_Preview;

   --  Route simulated mouse edits through the session.
   procedure Submit_Mouse_Command (Line : String) is
   begin
      Run (Line, Expect_Mouse_Success);
   end Submit_Mouse_Command;

   function Clip_Box (Name : String) return Rectangle is
   begin
      for I in 1 .. Item_Count (+H) loop
         declare
            Label : constant Item := Get_Item (+H, I);
         begin
            if Label.Kind = Text_Item and then To_String (Label.Text_Content) = Name then
               return Get_Item (+H, I - 1).Geometry;
            end if;
         end;
      end loop;
      return (0.0, 0.0, 0.0, 0.0);
   end Clip_Box;

   function Razor_Guide return Rectangle is
   begin
      for I in 1 .. Item_Count (+H) loop
         declare
            Drawn : constant Item := Get_Item (+H, I);
         begin
            if Drawn.Kind = Panel_Item and then Drawn.Part = Cursor_Part then
               return Drawn.Geometry;
            end if;
         end;
      end loop;
      return (0.0, 0.0, 0.0, 0.0);
   end Razor_Guide;

   procedure Rebuild is
      V : Timeline_View.Views.Ref := Timeline_View.Views.Borrow (H);
   begin
      Timeline_View.Build_Items (V.Ptr.all);
   end Rebuild;

begin
   Set_Geometry (+H, (0.0, 0.0, 1000.0, 450.0));
   declare
      V : Timeline_View.Views.Ref := Timeline_View.Views.Borrow (H);
   begin
      V.Read_Sequence := Read_Sequence'Unrestricted_Access;
      V.Preview_Changed := Record_Preview'Unrestricted_Access;
      V.Submit_Command := Submit_Mouse_Command'Unrestricted_Access;
   end;
   Run ("load ../examples/cut.fw");
   Rebuild;
   pragma Assert (Clip_Box ("c1") = (110.0, 34.0, 208.0, 36.0));
   pragma Assert (Clip_Box ("c2") = (382.0, 34.0, 160.0, 36.0));
   pragma Assert (Clip_Box ("c3") = (558.0, 34.0, 256.0, 36.0));
   pragma Assert (Clip_Box ("m1") = (110.0, 82.0, 704.0, 36.0));
   declare
      V : Timeline_View.Views.Ref := Timeline_View.Views.Borrow (H);
      use Adi.SDL.Mouse;
   begin
      pragma Assert (Timeline_View.Cursor_At (V.Ptr.all, 200.0, 10.0) = SDL_SYSTEM_CURSOR_EW_RESIZE);
      pragma Assert (Timeline_View.Cursor_At (V.Ptr.all, 111.0, 50.0) = SDL_SYSTEM_CURSOR_EW_RESIZE);
      pragma Assert (Timeline_View.Cursor_At (V.Ptr.all, 200.0, 50.0) = SDL_SYSTEM_CURSOR_MOVE);
      pragma Assert (Timeline_View.Cursor_At (V.Ptr.all, 350.0, 50.0) = SDL_SYSTEM_CURSOR_DEFAULT);
      V.Razor_Mode := True;
      pragma Assert (Timeline_View.Cursor_At (V.Ptr.all, 200.0, 50.0) = SDL_SYSTEM_CURSOR_DEFAULT);
      V.Razor_Mode := False;
      V.Drag_Active := True;
      pragma Assert (Timeline_View.Cursor_At (V.Ptr.all, -200.0, 50.0) = SDL_SYSTEM_CURSOR_MOVE);
      V.Drag_Trim_Left := True;
      pragma Assert (Timeline_View.Cursor_At (V.Ptr.all, -200.0, 50.0) = SDL_SYSTEM_CURSOR_EW_RESIZE);
      V.Drag_Active := False;
      V.Drag_Trim_Left := False;
   end;
   --  The razor guide is a clip-local overlay, never a document edit.
   declare
      V : Timeline_View.Views.Ref := Timeline_View.Views.Borrow (H);
      History_Before : constant Natural := FS.History_Length (S);
   begin
      V.Razor_Mode := True;
      Timeline_View.Set_Razor_Pointer (V.Ptr.all, 200.0, 50.0, True);
      Timeline_View.Build_Items (V.Ptr.all);
      pragma Assert (Razor_Guide = (200.0, 34.0, 2.0, 36.0));
      Timeline_View.Set_Razor_Pointer (V.Ptr.all, 350.0, 50.0, True);
      Timeline_View.Build_Items (V.Ptr.all);
      pragma Assert (Razor_Guide.Width = 0.0);
      Timeline_View.Set_Razor_Pointer (V.Ptr.all, 110.0, 50.0, True);
      Timeline_View.Build_Items (V.Ptr.all);
      pragma Assert (Razor_Guide.Width = 0.0);
      V.Zoom := 64.0;
      V.First_Second := 5.0;
      Timeline_View.Set_Razor_Pointer (V.Ptr.all, 398.0, 50.0, True);
      Timeline_View.Build_Items (V.Ptr.all);
      pragma Assert (Razor_Guide = (398.0, 34.0, 2.0, 36.0));
      Timeline_View.Set_Razor_Pointer (V.Ptr.all, 398.0, 50.0, False);
      Timeline_View.Build_Items (V.Ptr.all);
      pragma Assert (Razor_Guide.Width = 0.0);
      Timeline_View.Set_Razor_Pointer (V.Ptr.all, 398.0, 50.0, True);
      V.Razor_Mode := False;
      Timeline_View.Build_Items (V.Ptr.all);
      pragma Assert (Razor_Guide.Width = 0.0);
      pragma Assert (FS.History_Length (S) = History_Before);
      V.Zoom := 32.0;
      V.First_Second := 0.0;
   end;
   --  Scrub the ruler across a video end, a gap with music, and the
   --  next clip's first tick. Release over the clip row, even in razor mode.
   declare
      V : Timeline_View.Views.Ref := Timeline_View.Views.Borrow (H);
      History : constant Natural := FS.History_Length (S);
   begin
      V.Razor_Mode := True;
      Timeline_View.On_Mouse_Down (V.Ptr.all, 110.0, 10.0, Left_Button);
      pragma Assert (To_String (Last_Preview) = "c1 | 0 s");
      Timeline_View.On_Mouse_Move (V.Ptr.all, 318.0, 10.0);
      pragma Assert (To_String (Last_Preview) = "No video clip | 6.5 s");
      Timeline_View.On_Mouse_Up (V.Ptr.all, 382.0, 50.0, Left_Button);
      pragma Assert (To_String (Last_Preview) = "c2 | 8.5 s");
      Timeline_View.On_Mouse_Move (V.Ptr.all, 400.0, 50.0);
      pragma Assert (not V.Scrubbing and then not V.Drag_Active);
      Timeline_View.Build_Items (V.Ptr.all);
      pragma Assert (Get_Item (+H, Item_Count (+H)).Geometry = (382.0, 0.0, 2.0, 450.0));
      pragma Assert (FS.History_Length (S) = History);
      V.Razor_Mode := False;
   end;

   --  Clicking without dragging should leave the clip unchanged.
   declare
      V : Timeline_View.Views.Ref := Timeline_View.Views.Borrow (H);
   begin
      Timeline_View.On_Mouse_Down
        (V.Ptr.all, 600.0, 50.0, Left_Button);
      Timeline_View.On_Mouse_Up
        (V.Ptr.all, 600.0, 50.0, Left_Button);
   end;
   Rebuild;
   pragma Assert (Clip_Box ("c3").X = 558.0);

   --  Drag c3 left by 16 pixels (0.5 seconds at 32 px/s).
   declare
      V : Timeline_View.Views.Ref := Timeline_View.Views.Borrow (H);
   begin
      Timeline_View.On_Mouse_Down
        (V.Ptr.all, 600.0, 50.0, Left_Button);
      Timeline_View.On_Mouse_Up
        (V.Ptr.all, 584.0, 50.0, Left_Button);
   end;
   Rebuild;

   --  c3 should move from 14 seconds to 13.5 seconds.
   pragma Assert (Clip_Box ("c3").X = 542.0);

   --  Moving c3 onto c2 must report the error and preserve the accepted move.
   declare
      V : Timeline_View.Views.Ref := Timeline_View.Views.Borrow (H);
      History : constant Natural := FS.History_Length (S);
   begin
      Expect_Mouse_Success := False;
      Timeline_View.On_Mouse_Down (V.Ptr.all, 600.0, 50.0, Left_Button);
      Timeline_View.On_Mouse_Up (V.Ptr.all, 488.0, 50.0, Left_Button);
      Expect_Mouse_Success := True;
      pragma Assert (FS.Image (R) = "err cannot move: unknown clip or overlap");
      pragma Assert (FS.History_Length (S) = History);
   end;
   Rebuild;
   pragma Assert (Clip_Box ("c3").X = 542.0);

   --  Undo should restore the original clip position.
   Run ("undo");
   Rebuild;
   pragma Assert (Clip_Box ("c3").X = 558.0);
   --  Dragging the right edge should shorten c3 by one second.
   declare
      V : Timeline_View.Views.Ref := Timeline_View.Views.Borrow (H);
   begin
      --  c3 spans X = 558 to X = 814.
      --  Drag its right edge left by 32 pixels (one second).
      Timeline_View.On_Mouse_Down
        (V.Ptr.all, 810.0, 50.0, Left_Button);
      Timeline_View.On_Mouse_Up
        (V.Ptr.all, 778.0, 50.0, Left_Button);
   end;
   Rebuild;

   --  Start position stays the same; duration decreases.
   pragma Assert (Clip_Box ("c3").X = 558.0);
   pragma Assert (Clip_Box ("c3").Width = 224.0);

   --  Undo restores the original clip duration.
   Run ("undo");
   Rebuild;
   pragma Assert (Clip_Box ("c3").X = 558.0);
   pragma Assert (Clip_Box ("c3").Width = 256.0);
   --  Razor Mode should split c3 into two adjacent clips.
   declare
      V : Timeline_View.Views.Ref := Timeline_View.Views.Borrow (H);
      History_Before : constant Natural := FS.History_Length (S);
   begin
      V.Razor_Mode := True;

      --  Click inside c3 at X = 650.
      Timeline_View.On_Mouse_Down
        (V.Ptr.all, 650.0, 50.0, Left_Button);

      V.Razor_Mode := False;

      --  One split should create exactly one history entry.
      pragma Assert (FS.History_Length (S) = History_Before + 1);
   end;
   Rebuild;

   --  The two clips should preserve the original timeline duration.
   pragma Assert (Clip_Box ("c3").X = 558.0);
   pragma Assert (Clip_Box ("r1").Width > 0.0);
   pragma Assert
     (Clip_Box ("c3").Width + Clip_Box ("r1").Width = 256.0);
   pragma Assert
     (Clip_Box ("r1").X =
      Clip_Box ("c3").X + Clip_Box ("c3").Width);

   --  One undo should reverse the entire split.
   Run ("undo");
   Rebuild;
   pragma Assert (Clip_Box ("r1").Width = 0.0);
   pragma Assert (Clip_Box ("c3").Width = 256.0);

   --  Clicking a clip selects it without changing the timeline.
   declare
      V : Timeline_View.Views.Ref := Timeline_View.Views.Borrow (H);
      History_Before : constant Natural := FS.History_Length (S);
   begin
      Timeline_View.On_Mouse_Down
        (V.Ptr.all, 600.0, 50.0, Left_Button);
      Timeline_View.On_Mouse_Up
        (V.Ptr.all, 600.0, 50.0, Left_Button);

      pragma Assert (To_String (V.Selected_Clip) = "c3");
      pragma Assert (FS.History_Length (S) = History_Before);
   end;

   --  Deleting the selected clip removes it from the timeline.
   Run ("delete c3");
   Rebuild;
   pragma Assert (Clip_Box ("c3").Width = 0.0);

   --  A single undo restores the deleted clip.
   Run ("undo");
   Rebuild;
   pragma Assert (Clip_Box ("c3").X = 558.0);
   pragma Assert (Clip_Box ("c3").Width = 256.0);




   --  A failed engine edit must leave the drawn geometry unchanged.
   Run ("move c3 10", False);
   Rebuild;
   pragma Assert (Clip_Box ("c3").X = 558.0);
   Run ("move c3 13.5");
   Rebuild;
   pragma Assert (Clip_Box ("c3").X = 542.0);
   declare
      V : Timeline_View.Views.Ref := Timeline_View.Views.Borrow (H);
      History : constant Natural := FS.History_Length (S);
   begin
      V.Zoom := 64.0;
      V.First_Second := 5.0;
      Timeline_View.On_Mouse_Down (V.Ptr.all, 334.0, 10.0, Left_Button);
      pragma Assert (To_String (Last_Preview) = "c2 | 8.5 s");
      Timeline_View.On_Mouse_Up (V.Ptr.all, 10.0, 10.0, Left_Button);
      pragma Assert (To_String (Last_Preview) = "c1 | 5 s");
      Timeline_View.Build_Items (V.Ptr.all);
      pragma Assert (FS.History_Length (S) = History);
   end;
   --  c1 begins offscreen and is clipped at the timeline's left edge.
   pragma Assert (Clip_Box ("c1") = (110.0, 34.0, 96.0, 36.0));
   Run ("delete c1");
   Rebuild;
   pragma Assert (Clip_Box ("c1").Width = 0.0);
   Run ("undo");
   Rebuild;
   pragma Assert (Clip_Box ("c1").Width = 96.0);
   while FS.History_Length (S) > 0 loop
      Run ("undo");
   end loop;
   Rebuild;
   pragma Assert (Clip_Box ("m1").Width = 0.0);
   --  A fresh fixture isolates snap targets from prior editing tests.
   Run ("import source source.mp4 100 video");
   Run ("import music music.wav 100 audio");
   Run ("track v video");
   Run ("track a audio");
   Run ("place left v source 0 3.3 0");
   Run ("place dragged v source 0 2 5");
   Run ("place right v source 0 2 10");
   Run ("place soundtrack a music 0 13 0");
   declare
      use Adi.SDL.Events;
      V : Timeline_View.Views.Ref := Timeline_View.Views.Borrow (H);

      procedure Drop_At
        (Raw, Expected : Long_Float; Modifiers : SDL_Keymod;
         Zoom : Long_Float := 32.0; Success : Boolean := True;
         Interval : Framewise.Time := Framewise.Timebase / 2)
      is
         History : constant Natural := FS.History_Length (S);
         Grab : Pixel_Type;
         Target : Pixel_Type;
      begin
         V.Snap_Interval := Interval;
         V.Zoom := Zoom;
         V.First_Second := 0.0;
         V.Razor_Mode := False;
         Set_Modifiers (Modifiers);
         Rebuild;
         Grab := 110.0 + Pixel_Type (5.75 * Zoom);
         Target := Grab + Pixel_Type ((Raw - 5.0) * Zoom);
         Timeline_View.On_Mouse_Down (V.Ptr.all, Grab, 50.0, Left_Button);
         pragma Assert (V.Drag_Active and then not V.Drag_Trim_Left and then not V.Drag_Trim_Right);
         Timeline_View.On_Mouse_Move (V.Ptr.all, Target, 50.0);
         Rebuild;
         pragma Assert (abs (Clip_Box ("dragged").X - (110.0 + Pixel_Type (Expected * Zoom))) < 0.01,
                        "Drag preview must use snapped target");
         pragma Assert (FS.History_Length (S) = History, "Preview must not edit document");
         declare
            Ghost_Label, Other_Label : Natural := 0;
         begin
            for I in 1 .. Item_Count (+H) loop
               declare
                  Drawn : constant Item := Get_Item (+H, I);
               begin
                  if Drawn.Kind = Text_Item and then To_String (Drawn.Text_Content) = "dragged" then
                     Ghost_Label := I;
                  elsif Drawn.Kind = Text_Item and then To_String (Drawn.Text_Content) = "right" then
                     Other_Label := I;
                  end if;
               end;
            end loop;
            pragma Assert (Other_Label > 0 and then Ghost_Label > Other_Label + 1,
                           "Dragged panel and text must be painted after the other clips");
            pragma Assert (Get_Item (+H, Ghost_Label - 1).Kind = Panel_Item and then
              Get_Item (+H, Ghost_Label).Z_Order > Get_Item (+H, Ghost_Label - 1).Z_Order,
              "Dragged label stays above its own panel");
         end;
         Expect_Mouse_Success := Success;
         Timeline_View.On_Mouse_Up (V.Ptr.all, Target, 50.0, Left_Button);
         Expect_Mouse_Success := True;
         Set_Modifiers (0);
         Rebuild;
         if Success then
            pragma Assert (FS.History_Length (S) = History + 1, "Drop submits exactly one command");
            pragma Assert (abs (Clip_Box ("dragged").X - (110.0 + Pixel_Type (Expected * Zoom))) < 0.01,
                           "Accepted position must match drag preview");
            Run ("undo");
         else
            pragma Assert (FS.History_Length (S) = History, "Overlap remains rejected");
            pragma Assert (Clip_Box ("dragged").X = 110.0 + Pixel_Type (5.0 * Zoom));
         end if;
      end Drop_At;
   begin
      V.Playhead := 0;
      Drop_At (3.45, 3.45, 0);                  --  Free movement is unchanged.
      Drop_At (3.45, 3.3, SDL_KMOD_SHIFT);      --  Left edge touches left neighbor's end.
      Drop_At (7.85, 8.0, SDL_KMOD_SHIFT);      --  Right edge touches right neighbor's start.
      Drop_At (3.65, 3.65, SDL_KMOD_SHIFT);     --  Outside the 10-pixel attraction range.
      Drop_At (13.15, 13.15, SDL_KMOD_SHIFT);   --  Ignore the audio track's end at 13.
      Drop_At (3.5, 3.3, SDL_KMOD_SHIFT, 32.0);
      Drop_At (3.5, 3.5, SDL_KMOD_SHIFT, 64.0); --  Same time gap, farther apart on screen.
      Drop_At (6.24, 6.0, SDL_KMOD_CTRL);
      Drop_At (6.26, 6.5, SDL_KMOD_CTRL);
      Drop_At (6.25, 6.5, SDL_KMOD_CTRL);       --  Halfway rounds toward the later interval.
      Drop_At (6.12, 6.0, SDL_KMOD_CTRL, Interval => Framewise.Timebase / 4);
      Drop_At (6.14, 6.25, SDL_KMOD_CTRL, Interval => Framewise.Timebase / 4);
      Drop_At (6.26, 6.0, SDL_KMOD_CTRL, Interval => Framewise.Timebase);
      Drop_At (6.15, 6.2, SDL_KMOD_CTRL, Interval => Framewise.Timebase / 10);
      Drop_At (6.24, 6.24, SDL_KMOD_CTRL, Interval => 0);

      Drop_At (3.45, 3.3, SDL_KMOD_SHIFT or SDL_KMOD_CTRL);
      Drop_At (6.24, 6.0, SDL_KMOD_SHIFT or SDL_KMOD_CTRL);
      Drop_At (9.8, 10.0, SDL_KMOD_CTRL, Success => False);

      --  Shift can align either clip edge to the playhead, including when
      --  competing with neighbors. Preview and release must agree.
      V.Playhead := Framewise.Time (6.3 * Long_Float (Framewise.Timebase));
      Drop_At (6.15, 6.3, SDL_KMOD_SHIFT);     --  Left edge meets the cursor.
      Drop_At (4.45, 4.3, SDL_KMOD_SHIFT);     --  Right edge meets the cursor.
      Drop_At (6.15, 6.15, 0);                --  No snapping without Shift.
      Drop_At (6.65, 6.65, SDL_KMOD_SHIFT);    --  Outside the attraction range.
      Drop_At (6.5, 6.5, SDL_KMOD_SHIFT, 64.0); --  Threshold uses screen pixels.
      Drop_At (6.15, 6.3, SDL_KMOD_SHIFT or SDL_KMOD_CTRL);
      V.Playhead := Framewise.Time (3.4 * Long_Float (Framewise.Timebase));
      Drop_At (3.45, 3.4, SDL_KMOD_SHIFT);     --  Cursor is closer than neighbor.
      V.Playhead := Framewise.Time (3.6 * Long_Float (Framewise.Timebase));
      Drop_At (3.35, 3.3, SDL_KMOD_SHIFT);     --  Neighbor is closer than cursor.
      V.Playhead := Framewise.Time (3.1 * Long_Float (Framewise.Timebase));
      Drop_At (3.2, 3.3, SDL_KMOD_SHIFT);      --  Cursor target would overlap.
      V.Playhead := Framewise.Time (12.1 * Long_Float (Framewise.Timebase));
      Drop_At (10.15, 10.15, SDL_KMOD_SHIFT, Success => False);
      V.Playhead := Framewise.Timebase / 2;   --  Clip cannot end before time zero.
      Drop_At (0.6, 0.6, SDL_KMOD_SHIFT, Success => False);
      V.Playhead := 0;

      --  Competing neighbors: select the closer valid edge rather than the first.
      Run ("move dragged 15");
      Run ("move right 5.6");
      Run ("move dragged 8");
      V.Zoom := 32.0;
      V.First_Second := 0.0;
      Set_Modifiers (SDL_KMOD_SHIFT);
      Timeline_View.On_Mouse_Down (V.Ptr.all, 390.0, 50.0, Left_Button);
      Timeline_View.On_Mouse_Move (V.Ptr.all, 245.04, 50.0);
      Timeline_View.On_Mouse_Up (V.Ptr.all, 245.04, 50.0, Left_Button);
      Set_Modifiers (0);
      Rebuild;
      pragma Assert (abs (Clip_Box ("dragged").X - 225.2) < 0.01, "Nearest gap edge is 3.6 seconds");
      Run ("undo");
      --  A neighboring gap smaller than the clip must not attract either edge.
      Run ("move right 4.8");
      declare
         History : constant Natural := FS.History_Length (S);
      begin
         Set_Modifiers (SDL_KMOD_SHIFT);
         Timeline_View.On_Mouse_Down (V.Ptr.all, 390.0, 50.0, Left_Button);
         Timeline_View.On_Mouse_Move (V.Ptr.all, 242.8, 50.0);
         Rebuild;
         pragma Assert (abs (Clip_Box ("dragged").X - 218.8) < 0.01,
                        "Invalid neighboring placements must not attract the preview");
         Expect_Mouse_Success := False;
         Timeline_View.On_Mouse_Up (V.Ptr.all, 242.8, 50.0, Left_Button);
         Expect_Mouse_Success := True;
         Set_Modifiers (0);
         pragma Assert (FS.History_Length (S) = History);
      end;
      Run ("move right 10");
      Run ("move dragged 5");

      --  Changing a modifier without moving the pointer updates the ghost too.
      Set_Modifiers (0);
      Timeline_View.On_Mouse_Down (V.Ptr.all, 294.0, 50.0, Left_Button);
      Timeline_View.On_Mouse_Move (V.Ptr.all, 333.68, 50.0); --  Raw start 6.24.
      Set_Modifiers (SDL_KMOD_CTRL);
      Timeline_View.On_Key_Down (V.Ptr.all, 224, SDL_KMOD_CTRL, False);
      Rebuild;
      pragma Assert (Clip_Box ("dragged").X = 302.0, "Pressing Control updates a stationary preview");
      Set_Modifiers (0);
      Timeline_View.On_Key_Up (V.Ptr.all, 224, 0, False);
      Rebuild;
      pragma Assert (abs (Clip_Box ("dragged").X - 309.68) < 0.01, "Releasing Control restores free preview");
      Timeline_View.On_Mouse_Up (V.Ptr.all, 333.68, 50.0, Left_Button);
      pragma Assert (FS.History_Line (S, FS.History_Length (S)) = "move dragged 6.24");
      Run ("undo");

      --  Trim previews and commands must use the same configured interval.
      declare
         procedure Trim_By
           (Left : Boolean; Delta_Seconds, Expected_In, Expected_Out : Long_Float;
            Interval : Framewise.Time; Modifiers : SDL_Keymod := SDL_KMOD_CTRL)
         is
            History : constant Natural := FS.History_Length (S);
            Grab : constant Pixel_Type := (if Left then 271.0 else 333.0);
            Target : constant Pixel_Type := Grab + Pixel_Type (Delta_Seconds * V.Zoom);
         begin
            V.Snap_Interval := Interval;
            Set_Modifiers (Modifiers);
            Timeline_View.On_Mouse_Down (V.Ptr.all, Grab, 50.0, Left_Button);
            pragma Assert (V.Drag_Active and then V.Drag_Trim_Left = Left);
            Timeline_View.On_Mouse_Move (V.Ptr.all, Target, 50.0);
            Rebuild;
            pragma Assert (abs (Clip_Box ("dragged").Width -
              Pixel_Type ((Expected_Out - Expected_In) * V.Zoom)) < 0.01,
              "Snapped trim preview uses source bounds");
            pragma Assert (FS.History_Length (S) = History);
            Timeline_View.On_Mouse_Up (V.Ptr.all, Target, 50.0, Left_Button);
            Set_Modifiers (0);
            pragma Assert (FS.History_Length (S) = History + 1);
            pragma Assert (FS.History_Line (S, FS.History_Length (S)) =
              "trim dragged " & FS.Image_Time (Framewise.Time (Expected_In * Long_Float (Framewise.Timebase))) &
              " " & FS.Image_Time (Framewise.Time (Expected_Out * Long_Float (Framewise.Timebase))));
            Rebuild;
            pragma Assert (abs (Clip_Box ("dragged").Width -
              Pixel_Type ((Expected_Out - Expected_In) * V.Zoom)) < 0.01);
            Run ("undo");
         end Trim_By;
      begin
         Trim_By (False, -0.26, 0.0, 1.5, Framewise.Timebase / 2);
         Trim_By (True, 0.26, 0.5, 2.0, Framewise.Timebase / 2);
         Trim_By (False, -0.36, 0.0, 1.75, Framewise.Timebase / 4);
         Trim_By (True, 0.36, 0.25, 2.0, Framewise.Timebase / 4);
         Trim_By (False, -0.26, 0.0, 1.5, Framewise.Timebase / 2, SDL_KMOD_CTRL or SDL_KMOD_SHIFT);
         Trim_By (False, -0.26, 0.0, 1.74, Framewise.Timebase / 2, 0);
         --  Rounding to a zero-length source window must not create an edit.
         declare
            History : constant Natural := FS.History_Length (S);
         begin
            V.Snap_Interval := Framewise.Timebase;
            Set_Modifiers (SDL_KMOD_CTRL);
            Timeline_View.On_Mouse_Down (V.Ptr.all, 333.0, 50.0, Left_Button);
            Timeline_View.On_Mouse_Up (V.Ptr.all, 272.2, 50.0, Left_Button);
            pragma Assert (FS.History_Length (S) = History);
         end;
      end;

      --  Scrubbing is a view action and must never enter the edit history.
      declare
         History : constant Natural := FS.History_Length (S);
      begin
         V.First_Second := 2.1;
         V.Zoom := 64.0;
         V.Snap_Interval := Framewise.Timebase / 4;
         Set_Modifiers (SDL_KMOD_CTRL);
         Timeline_View.On_Mouse_Down (V.Ptr.all, 138.16, 10.0, Left_Button); --  2.54 -> 2.5.
         pragma Assert (V.Playhead = Framewise.Timebase * 5 / 2);
         Timeline_View.On_Mouse_Move (V.Ptr.all, 146.48, 10.0); --  2.67 -> 2.75.
         pragma Assert (V.Playhead = Framewise.Timebase * 11 / 4);
         Set_Modifiers (0);
         Timeline_View.On_Key_Up (V.Ptr.all, 224, 0, False);
         pragma Assert (V.Playhead = Framewise.Time (2.67 * Long_Float (Framewise.Timebase)));
         Set_Modifiers (SDL_KMOD_CTRL);
         Timeline_View.On_Key_Down (V.Ptr.all, 224, SDL_KMOD_CTRL, False);
         pragma Assert (V.Playhead = Framewise.Timebase * 11 / 4);
         Timeline_View.On_Mouse_Up (V.Ptr.all, 146.48, 10.0, Left_Button);
         pragma Assert (V.Playhead = Framewise.Timebase * 11 / 4);
         pragma Assert (FS.History_Length (S) = History);
         Set_Modifiers (0);
         V.Zoom := 32.0;
         V.First_Second := 0.0;
         V.Snap_Interval := Framewise.Timebase / 2;
      end;
      Run ("move dragged 3.3");
      declare
         History : constant Natural := FS.History_Length (S);
      begin
         Set_Modifiers (SDL_KMOD_CTRL);
         Timeline_View.On_Mouse_Down (V.Ptr.all, 239.6, 50.0, Left_Button);
         Timeline_View.On_Mouse_Up (V.Ptr.all, 239.6, 50.0, Left_Button);
         Set_Modifiers (0);
         pragma Assert (FS.History_Length (S) = History, "Control-click without dragging must not move a clip");
      end;
   end;
   Ada.Text_IO.Put_Line ("PASS: neighbor/grid snapping, preview, modifier changes, zoom and overlap validation");
   declare
      Base : Widget_Handle := +H;
   begin
      Destroy (Base);
   end;
   Ada.Text_IO.Put_Line ("PASS: timeline geometry, playhead, zoom, session refresh and failed edits");
end Timeline_View_Tests;
