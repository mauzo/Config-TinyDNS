.include <mauzo.perl.mk>

root/data.cdb: root/data
	(cd root; tinydns-data)

root/data: all root/data.in
	(cd root; \
	blib tinydns-filter include vars site=mountplym lresolv rresolv \
		<data.in >data)
