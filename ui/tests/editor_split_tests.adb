with Ada.Text_IO;
with Adi.Core; use Adi.Core;
with Adi.Widget; use Adi.Widget;
with Adi.Widget.Box;
with Editor_Split;
with Adi.SDL.Mouse;

procedure Editor_Split_Tests is
   use type Editor_Split.Views.Handle;
   use type Adi.SDL.Mouse.SDL_SystemCursor;
   use type Adi.Widget.Box.Box_Handle;
   H : constant Editor_Split.Views.Handle := Editor_Split.Views.New_Widget;
   F : constant Adi.Widget.Box.Box_Handle := Adi.Widget.Box.Create_Handle;
   S : constant Adi.Widget.Box.Box_Handle := Adi.Widget.Box.Create_Handle;
begin
   Add_Child (+H, +F);
   Add_Child (+H, +S);
   Set_Geometry (+H, (10.0, 20.0, 1008.0, 600.0));
   declare
      V : Editor_Split.Views.Ref := Editor_Split.Views.Borrow (H);
   begin
      V.First := +F;
      V.Second := +S;
      V.Minimum_First := 200.0;
      V.Minimum_Second := 300.0;
      V.Fraction := 0.4;
      Editor_Split.Layout (V.Ptr.all);
      pragma Assert (Editor_Split.Cursor_At (V.Ptr.all, 414.0, 100.0) =
        Adi.SDL.Mouse.SDL_SYSTEM_CURSOR_EW_RESIZE);
      pragma Assert (Editor_Split.Cursor_At (V.Ptr.all, 20.0, 100.0) =
        Adi.SDL.Mouse.SDL_SYSTEM_CURSOR_DEFAULT);
      pragma Assert (Get_Geometry (+F).Width = 400.0);
      pragma Assert (Get_Geometry (+S).X = 418.0);
      Editor_Split.On_Mouse_Down (V.Ptr.all, 414.0, 100.0, Left_Button);
      Editor_Split.On_Mouse_Move (V.Ptr.all, 10000.0, 100.0);
      pragma Assert (Editor_Split.Cursor_At (V.Ptr.all, 10000.0, 100.0) =
        Adi.SDL.Mouse.SDL_SYSTEM_CURSOR_EW_RESIZE);
      Editor_Split.On_Mouse_Up (V.Ptr.all, 10000.0, 100.0, Left_Button);
      Editor_Split.Layout (V.Ptr.all);
      pragma Assert (Get_Geometry (+S).Width = 300.0);
      pragma Assert (not V.Dragging);
      Set_Geometry (+H, (10.0, 20.0, 208.0, 600.0));
      Editor_Split.Layout (V.Ptr.all);
      pragma Assert (Get_Geometry (+F).Width = 80.0);
      pragma Assert (Get_Geometry (+S).Width = 120.0);
      V.Vertical := True;
      V.Fraction := 0.5;
      Set_Geometry (+H, (10.0, 20.0, 800.0, 1008.0));
      Editor_Split.Layout (V.Ptr.all);
      pragma Assert (Editor_Split.Cursor_At (V.Ptr.all, 50.0, 524.0) =
        Adi.SDL.Mouse.SDL_SYSTEM_CURSOR_NS_RESIZE);
      pragma Assert (Get_Geometry (+F).Height = 500.0);
      pragma Assert (Get_Geometry (+S).Y = 528.0);
      Editor_Split.On_Mouse_Down (V.Ptr.all, 50.0, 524.0, Left_Button);
      Editor_Split.On_Mouse_Up (V.Ptr.all, 50.0, -500.0, Left_Button);
      Editor_Split.Layout (V.Ptr.all);
      pragma Assert (Get_Geometry (+F).Height = 200.0);
      pragma Assert (Get_Geometry (+S).Height = 800.0);
   end;
   Ada.Text_IO.Put_Line ("PASS: splitter geometry, drag bounds, small windows and both axes");
end Editor_Split_Tests;
