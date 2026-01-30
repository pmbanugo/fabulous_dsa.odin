package capnp

// Error codes for Cap'n Proto operations
Error :: enum {
	None,

	// Framing errors
	Invalid_Frame_Header,
	Segment_Count_Overflow,
	Segment_Size_Overflow,
	Unexpected_End_Of_Input,

	// Pointer errors
	Pointer_Out_Of_Bounds,
	Invalid_Pointer_Type,
	Null_Pointer,

	// Security errors
	Traversal_Limit_Exceeded,
	Nesting_Limit_Exceeded,

	// List errors
	Invalid_Element_Size,
	List_Index_Out_Of_Bounds,

	// Text/Data errors
	Text_Not_Nul_Terminated,
	Invalid_Utf8,

	// Allocation errors
	Out_Of_Memory,
	Segment_Full,

	// Packing errors
	Invalid_Packed_Data,
}
