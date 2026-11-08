with Adi.Widget; use Adi.Widget;
with Adi.OS;
with Editor_Context; use Editor_Context;

package Editor_Dialogs is
   function Field (Index : Positive) return String;

   procedure Set_Field (Index : Positive; Caption, Value : String);

   procedure Prepare_Form (New_Mode : Form_Mode; Title : String);

   procedure Form_Result (Dialog : Widget_Handle; Index : Natural; Caption : String);

   procedure Import_Selected (Files : Adi.OS.String_Array);

   procedure Build;
end Editor_Dialogs;
