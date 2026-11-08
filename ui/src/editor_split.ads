with Adi.Core;
with Adi.Widget;
with Adi.Widget.Extension;

package Editor_Split is
   type Split_Widget is new Adi.Widget.Widget with record
      First, Second : Adi.Widget.Widget_Handle := Adi.Widget.Null_Handle;
      Vertical : Boolean := False; -- True: panes above/below each other
      Fraction : Float := 0.5;
      Minimum_First, Minimum_Second : Adi.Core.Pixel_Type := 180.0;
      Dragging : Boolean := False;
   end record;

   Divider_Size : constant Adi.Core.Pixel_Type := 8.0;
   function First_Size (Extent : Adi.Core.Pixel_Type; Fraction : Float;
      Minimum_First, Minimum_Second : Adi.Core.Pixel_Type)
      return Adi.Core.Pixel_Type;
   overriding procedure Layout (W : in out Split_Widget);
   overriding procedure Build_Items (W : in out Split_Widget);
   overriding procedure On_Mouse_Down
     (W : in out Split_Widget; X, Y : Adi.Core.Pixel_Type;
      Button : Adi.Core.Mouse_Button; Clicks : Natural := 1);
   overriding procedure On_Mouse_Move
     (W : in out Split_Widget; X, Y : Adi.Core.Pixel_Type);
   overriding procedure On_Mouse_Up
     (W : in out Split_Widget; X, Y : Adi.Core.Pixel_Type;
      Button : Adi.Core.Mouse_Button);
   package Views is new Adi.Widget.Extension (Split_Widget);
end Editor_Split;
