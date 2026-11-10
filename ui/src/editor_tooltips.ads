with Adi.Widget;
package Editor_Tooltips is
   procedure Register (Owner : Adi.Widget.Widget_Handle; Text : String);
   function Hint_For (Owner : Adi.Widget.Widget_Handle) return String;
   procedure Build;
end Editor_Tooltips;
