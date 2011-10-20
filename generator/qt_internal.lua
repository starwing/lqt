
local classes = ...
local ret1 = {}

-- don't bind this Qt internals/unsupported classes
-- if there are linker errors, or errors when laoding the .so 
-- add the class here 

for c in pairs(classes) do
	local n = c.name
	if n~=string.lower(n) and not (string.match(n, '_')
			-- these are useless to bind, but compile
			or c.fullname=='QVariant::Private' -- well, it IS public
			or c.fullname=='QVariant::Private::Data' -- well, it IS public
			or c.fullname=='QVariant::PrivateShared' -- well, it IS public
			or c.fullname=='QObjectData'-- compiles
			or c.fullname=='QtConcurrent::internal::ExceptionStore' -- it compiles
			or c.fullname=='QtConcurrent::internal::ExceptionHolder' -- it compiles
			or c.fullname=='QtConcurrent::ResultIteratorBase' -- it compiles
			or c.fullname=='QtSharedPointer' -- compiles
			or c.fullname=='QtSharedPointer::InternalRefCountData' -- compiles
			or c.fullname=='QtSharedPointer::ExternalRefCountData' -- compiles
			or c.fullname=='QUpdateLaterEvent' -- compiles
			or c.fullname=='QTextStreamManipulator' -- compiles
			or c.fullname=='QtConcurrent::ThreadEngineSemaphore' -- compiles
			or c.fullname=='QtConcurrent::ThreadEngineBarrier' -- linker error
			
			-- platform specific, TODO
			or c.fullname=='QWindowsCEStyle'
			or c.fullname=='QWindowsMobileStyle'
			or c.fullname=='QWindowsXPStyle'
			or c.fullname=='QWindowsVistaStyle'
			or c.fullname=='QMacStyle'
			or c.fullname=='QS60Style'
			or c.fullname=='QS60MainApplication'
			or c.fullname=='QS60MainAppUI'
			or c.fullname=='QS60MainDocument'
			or c.fullname=='QWSCalibratedMouseHandler'
			or c.fullname=='QWSClient'
			or c.fullname=='QWSEmbedWidget'
			or c.fullname=='QWSEvent'
			or c.fullname=='QWSGLWindowSurface'
			or c.fullname=='QWSInputMethod'
			or c.fullname=='QWSKeyboardHandler'
			or c.fullname=='QWSMouseHandler'
			or c.fullname=='QWSPointerCalibrationData'
			or c.fullname=='QWSScreenSaver'
			or c.fullname=='QWSServer'
			or c.fullname=='QWSWindow'
			or c.fullname=='QXmlNodeModelIndex' -- a method "name" is public but is not part of the documented API
			or c.fullname=='QXmlName' -- a method "localName" is public but is not part of the documented API

			-- binding bugs
			or c.fullname=='QThreadStorageData' -- binding error (function pointer)
			or c.fullname=='QForeachContainerBase' -- "was not declared in this scope"
			or c.fullname=='QFutureWatcherBase' -- const virtual method causes it to be abstract
			or c.fullname=='QEasingCurve'        -- wrapper for function: function pointer parsing problem
			or c.fullname=='QHashData'        -- not in the docs at all. free_helper is not present during compilation
			or string.match(c.fullname, '^QtConcurrent') -- does not make sense anyway, because we should duplicate the lua_State
			or string.match(c.fullname, '^QAccessible') -- causes a lot of headaches, and not necessarry anyway (yet)
			or string.match(c.fullname, 'Private$') -- should not bind these
			) then
		ret1[c] = true
	else
		ignore(c.fullname, "blacklisted", "filter")
	end
end

return ret1

