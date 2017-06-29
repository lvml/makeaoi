

makeaoi: makeaoi.tcl makeaoi_aux/AppRun makeaoi_aux/aoi_support_binaries/*
	@echo "Notice: You can also invoke 'makeaoi.tcl' directly, without making 'makeaoi', if makeaoi_aux is present."
	@echo "creating makeaoi from makeaoi.tcl by appending a base64-encoded tar.gz archive of makeaoi_aux:"
	cp makeaoi.tcl makeaoi
	tools/tar_to_base64_tcl makeaoi_aux >>makeaoi
	chmod 755 makeaoi
	@echo "makeaoi created, it can be run stand-alone, without requiring the makeaoi_aux directory."
