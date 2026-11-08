with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Text_IO;
with Adi.Core; use Adi.Core;
with Adi.Widget; use Adi.Widget;
with Framewise.Session;
with Timeline_View;
with Adi.SDL.Mouse;

procedure Timeline_View_Tests is
   package FS renames Framewise.Session;
   S : FS.Session;
   R : FS.Response;
   H : Timeline_View.Views.Handle := Timeline_View.Views.New_Widget;
   use type Timeline_View.Views.Handle;
   use type Adi.SDL.Mouse.SDL_SystemCursor;
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
      pragma Assert (Timeline_View.Cursor_At (V.Ptr.all, 200.0, 50.0) = SDL_SYSTEM_CURSOR_CROSSHAIR);
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
   declare
      Base : Widget_Handle := +H;
   begin
      Destroy (Base);
   end;
   Ada.Text_IO.Put_Line ("PASS: timeline geometry, playhead, zoom, session refresh and failed edits");
end Timeline_View_Tests;
