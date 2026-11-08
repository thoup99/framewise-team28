with Adi.Widget; use Adi.Widget;
with Editor_Context; use Editor_Context;

package Editor_Widgets is
   --  Common widget creation keeps style and callback wiring consistent.
   function Make_Label (Parent : Widget_Handle; Text : String) return Labels.Label_Handle;

   function Make_Button (Parent : Widget_Handle; Text : String) return Buttons.Button_Handle;

   procedure Add_Label (Parent : Widget_Handle; Text : String);
end Editor_Widgets;
