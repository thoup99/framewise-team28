with Adi.Core; use Adi.Core;
with Adi.Widget; use Adi.Widget;

package body Editor_Split is
   function First_Size (Extent : Pixel_Type; Fraction : Float;
      Minimum_First, Minimum_Second : Pixel_Type) return Pixel_Type
   is
      Available : constant Pixel_Type := Pixel_Type'Max (0.0, Extent - Divider_Size);
      Total : constant Pixel_Type := Minimum_First + Minimum_Second;
      Low : constant Pixel_Type :=
        (if Total > Available and then Total > 0.0
         then Available * Minimum_First / Total else Minimum_First);
      High : constant Pixel_Type :=
        (if Total > Available then Low else Available - Minimum_Second);
   begin
      return Pixel_Type'Max (Low, Pixel_Type'Min (High, Available * Pixel_Type (Fraction)));
   end First_Size;

   function Divider (W : Split_Widget) return Rectangle is
      G : constant Rectangle := Get_Geometry (W);
      Size : constant Pixel_Type := First_Size
        ((if W.Vertical then G.Height else G.Width), W.Fraction,
         W.Minimum_First, W.Minimum_Second);
   begin
      return (if W.Vertical then
        (G.X, G.Y + Size, G.Width, Pixel_Type'Min (Divider_Size, G.Height))
        else (G.X + Size, G.Y, Pixel_Type'Min (Divider_Size, G.Width), G.Height));
   end Divider;

   function Cursor_At (W : Split_Widget; X, Y : Pixel_Type)
      return Adi.SDL.Mouse.SDL_SystemCursor
   is
      use Adi.SDL.Mouse;
      D : constant Rectangle := Divider (W);
   begin
      if W.Dragging or else
        (X >= D.X and then X <= D.X + D.Width and then
         Y >= D.Y and then Y <= D.Y + D.Height)
      then
         return (if W.Vertical then SDL_SYSTEM_CURSOR_NS_RESIZE
                 else SDL_SYSTEM_CURSOR_EW_RESIZE);
      end if;
      return SDL_SYSTEM_CURSOR_DEFAULT;
   end Cursor_At;

   overriding procedure Layout (W : in out Split_Widget) is
      G : constant Rectangle := Get_Geometry (W);
      D : constant Rectangle := Divider (W);

   begin
      if not Is_Valid (W.First) or else not Is_Valid (W.Second) then
         return;
      end if;
      declare
         F : Widget_Ref := Borrow (W.First);
         S : Widget_Ref := Borrow (W.Second);
      begin
      if W.Vertical then
         Set_Geometry (W.First, (G.X, G.Y, G.Width, D.Y - G.Y));
         Set_Geometry (W.Second, (G.X, D.Y + D.Height, G.Width,
           Pixel_Type'Max (0.0, G.Y + G.Height - D.Y - D.Height)));
      else
         Set_Geometry (W.First, (G.X, G.Y, D.X - G.X, G.Height));
         Set_Geometry (W.Second, (D.X + D.Width, G.Y,
           Pixel_Type'Max (0.0, G.X + G.Width - D.X - D.Width), G.Height));
      end if;
      Layout_Child (F.Ptr.all);
      Layout_Child (S.Ptr.all);
      end;
   end Layout;

   overriding procedure Build_Items (W : in out Split_Widget) is
   begin
      Clear_Items (W);
      Add_Item (W, Make_Panel (Indicator_Part, Divider (W), 1));
   end Build_Items;

   overriding procedure On_Mouse_Down
     (W : in out Split_Widget; X, Y : Pixel_Type;
      Button : Mouse_Button; Clicks : Natural := 1)
   is
      pragma Unreferenced (Clicks);
      D : constant Rectangle := Divider (W);
   begin
      if Button = Left_Button and then X >= D.X and then X <= D.X + D.Width
        and then Y >= D.Y and then Y <= D.Y + D.Height
      then
         W.Dragging := True;
      end if;
   end On_Mouse_Down;

   overriding procedure On_Mouse_Move
     (W : in out Split_Widget; X, Y : Pixel_Type)
   is
      G : constant Rectangle := Get_Geometry (W);
      Available : constant Pixel_Type :=
        (if W.Vertical then G.Height else G.Width) - Divider_Size;
      Offset : constant Pixel_Type := (if W.Vertical then Y - G.Y else X - G.X);
   begin
      if W.Dragging and then Available > 0.0 then
         W.Fraction := Float (First_Size
           (Available + Divider_Size, Float (Offset / Available),
            W.Minimum_First, W.Minimum_Second) / Available);
         Mark_Dirty (W);
      end if;
   end On_Mouse_Move;

   overriding procedure On_Mouse_Up
     (W : in out Split_Widget; X, Y : Pixel_Type; Button : Mouse_Button) is
   begin
      if Button = Left_Button then
         On_Mouse_Move (W, X, Y);
         W.Dragging := False;
      end if;
   end On_Mouse_Up;
end Editor_Split;
