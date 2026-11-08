with Adi.SDL.Events;

package Editor_Console is
   procedure Build;

   procedure Show;

   --  Handle only console-specific keys; ordinary editing stays with the input.
   procedure Handle_Key
     (Scancode : Adi.SDL.Events.SDL_Scancode;
      Repeat : Boolean; Handled : in out Boolean);
end Editor_Console;
