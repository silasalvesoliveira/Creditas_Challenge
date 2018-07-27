class CreateOrderAndInvoice
	attr_reader :productChoice
	
	def initialize(productChoice:)
		@productChoice = productChoice		
	end
	
	def run
	
		# Check if product type is according
		if !["physicItem", "service", "book", "digitalMedia"].include? productChoice[1]
			raise ArgumentError.new("A configuração do produto está incorreta. Entre em contato com o suporte.")
		end
	
		# Initialize customer
		customer = Customer.new(name: "José da Silva Carneiro", documentNum: "30125728050", birthDate: "1962-07-26", email: "josecarneiro@yahoo.com")
		
		# Initialize billing address
		billingAddress = Address.new(zipcode: "04571-010", street: "Av. Engenheiro Luís Carlos Berrini", number: "105", complement: "12 andar", referencePoint: "", 
									 district: "Brooklin Paulista", city: "São Paulo", state: "SP", country: "BR", addressType: :billing)
									 
		# Initialize shipping address
		shippingAddress = Address.new(zipcode: "04571-010", street: "Av. Engenheiro Luís Carlos Berrini", number: "105", complement: "11 andar", referencePoint: "Creditas", 
									 district: "Brooklin Paulista", city: "São Paulo", state: "SP", country: "BR", addressType: :shipping)
		
		# Initialize product
		product = Product.new(name: productChoice[0], type: productChoice[1], price: productChoice[2])
		
		# Initialize order
		order = Order.new(customer, billingAddress: billingAddress, shippingAddress: shippingAddress)
		order.add_product(product)

		# Initialize payment
		payment = Payment.new(order: order, payment_method: CreditCard.fetch_by_hashed('43567890-987654367'))
		payment.pay
				
		# If payment accepted, finalize process
		if payment.paid?
			puts "==> Pedido gerado com sucesso."
		end	
	end
end

class Payment
  attr_reader :authorization_number, :amount, :invoice, :order, :payment_method, :paid_at

  def initialize(attributes = {})
    @authorization_number, @amount = attributes.values_at(:authorization_number, :amount)
    @invoice, @order = attributes.values_at(:invoice, :order)
    @payment_method = attributes.values_at(:payment_method)
  end

  def pay(paid_at = Time.now)
    @amount = order.total_amount
    @authorization_number = Time.now.to_i
    @invoice = Invoice.new(order: order).close(paid_at, @authorization_number)
    @paid_at = paid_at
    order.close(@paid_at)
  end

  def paid?
    !paid_at.nil?
  end
end

class Invoice
  attr_reader :order

  def initialize(attributes = {})    
    @order = attributes.values_at(:order)
	@invoiceId = Time.now.to_i;
  end
  
  def close(closed_at = Time.now, authorization_number)	
	case @order.first.items.first.product.type
	when "physicItem"
		shippingLabel = CreateShippingLabel.new(order: order).run		
	when "service"
		sendEmail = CreateAndSendEmail.new(order: order).run(authorization_number)
	when "book"
		shippingLabel = CreateShippingLabel.new(order: order).run
	when "digitalMedia"
		sendEmail = CreateAndSendEmail.new(order: order).run(authorization_number)
	else
		raise ArgumentError.new("A opção é inválida. Tente novamente.")
	end
  end
end

class Order
  attr_reader :customer, :items, :payment, :billingAddress, :shippingAddress, :closed_at

  def initialize(customer, overrides = {})
    @customer = customer
    @items = []
    @order_item_class = overrides.fetch(:item_class) { OrderItem }    
	@billingAddress = overrides.fetch(:billingAddress)
	@shippingAddress = overrides.fetch(:shippingAddress)
  end

  def add_product(product)
    @items << @order_item_class.new(order: self, product: product)
  end

  def total_amount
    @items.map(&:total).inject(:+)
  end

  def close(closed_at = Time.now)
    @closed_at = closed_at
  end

  # remember: you can create new methods inside those classes to help you create a better design
end

class OrderItem
  attr_reader :order, :product

  def initialize(order:, product:)
    @order = order
    @product = product
  end

  def total
    product.price
  end
end

class Product
  # use type to distinguish each kind of product: physical, book, digital, membership, etc.
  attr_reader :name, :type, :price

  def initialize(name:, type:, price:)
    @name = name
	@type = type
	@price = price
  end
end

class Address
  attr_reader :zipcode, :street, :number, :complement, :referencePoint, :district, :city, :state, :country, :addressType

  def initialize(zipcode:, street:, number:, complement:, referencePoint:, district:, city:, state:, country:, addressType:)
    @zipcode = zipcode
	@street = street
	@number = number # String because exists 'S/N' value
	@complement = complement
	@referencePoint = referencePoint
	@district = district
	@city = city
	@state = state
	@country = country
	@addressType = addressType # This information is necessary if saving in DB
  end
end

class CreditCard
  def self.fetch_by_hashed(code)
    CreditCard.new
  end
end

class Customer
  attr_reader :name, :documentNum, :birthDate, :email

  def initialize(name:, documentNum:, birthDate:, email:)
    @name = name
    @documentNum = documentNum
	@birthDate = birthDate
	@email = email
  end
end

class Membership
  # you can customize this class by yourself
end

class CreateAndSendEmail
	attr_reader :order
	
	def initialize(order:)
		@order = order    
	end
	
	def run(authorization_number)
		customer = order.first.customer
		
		# Not implement HTML format, because is a simple presentation
		mailBody = "Olá #{customer.name}, \n";
		
		if order.first.items.first.product.type == "service"
			# Enable service licence
			serviceSubscription = EnableServiceOrLicenseSubscription.new(order: order)			
			
			mailBody = mailBody + "Sua assinatura para '#{order.first.items.first.product.name}' foi gerada com sucesso! \n" +
									"Acesse agora mesmo pelo link #{serviceSubscription.generateSubscription} e tenha uma excelente experiência.\n"			
		elsif order.first.items.first.product.type == "digitalMedia"				
			# Enable service licence
			serviceSubscription = EnableServiceOrLicenseSubscription.new(order: order)			
			# Generate voucher
			@discountValue = 10.00
			voucher = GenerateVoucher.new(order: order, discountValue: @discountValue)
			
			mailBody = mailBody + "O(a) '#{order.first.items.first.product.name}' já está disponível para ser utilizado!\n" +
									"Acesse agora mesmo pelo link #{serviceSubscription.generateSubscription} e se divirta.\n" +
									"E mais: você ganhou um cupom de desconto de R$ #{format("%.2f", @discountValue)} na sua próxima compra! \n" +
									"Use o código #{voucher.generateDiscountVoucher} no carrinho de compras.\n\n" +
									"Informações da sua compra:\n" +
									"Método de pagamento: Cartão de crédito \n" +
									"Número de autorização: #{authorization_number} \n" +
									"Valor total da compra: R$ #{format("%.2f", order.first.total_amount)} \n"
		else
			raise "O tipo do produto não está de acordo para o envio do e-mail."
		end
		
		mailBody = mailBody + "Agaradecemos pela preferência e em caso de problemas contate o nosso suporte.\n" +
								"Atenciosamente, \n" +
								"Equipe de vendas Creditas"
		
		# Send email method (SMTP or other) here
		# Use customer.email info
		
		puts mailBody
		puts "=> Email enviado com sucesso"		
	end
end

class CreateShippingLabel
	attr_reader :order
	
	def initialize(order:)
		@order = order    
	end
	
	def run
		customer = order.first.customer
		shippingAddress = order.first.shippingAddress		
		label = "\nDestinatário: #{customer.name} \n" +
				"Logradouro: #{shippingAddress.street} - Nº #{shippingAddress.number} \n" +
				"Complemento: #{shippingAddress.complement} - Ponto de ref.: #{shippingAddress.referencePoint} \n" +
				"Bairro: #{shippingAddress.district} - Cidade: #{shippingAddress.city} \n" +
				"CEP: #{shippingAddress.zipcode} - País: #{shippingAddress.country} \n"
						
		if order.first.items.first.product.type == "physicItem"
			# Print custom information label to physical item
		elsif order.first.items.first.product.type == "book"
			# Print custom information label to book
			label = label + "*Observação: conforme Art. 150, inc. VI, 'd' da Constituição Federal de 88, é vedado à União, " +
							"aos Estados, ao Distrito Federal e aos Municípios, instituir impostos sobre livros, jornais, " +
							"periódicos e o papel destinado a sua impressão. \n"			
		else
			raise "O tipo do produto não está de acordo para o emissão da etiqueta para envio."			
		end
		
		# Add information FROM on shiiping label here
		# Use company information for this
		
		puts label
		puts "=> Etiqueta gerada com sucesso"
	end
end

class EnableServiceOrLicenseSubscription
	attr_reader :order
	
	def initialize(order:)
		@order = order		
	end
	
	def generateSubscription
		@serviceLink = "https://subscriptionservice.creditas.com.br/user/" + order.first.customer.documentNum		
		# Save enable service os license on DB here
	end
end

class GenerateVoucher
	attr_reader :order, :discountValue
	
	def initialize(order:, discountValue:)
		@order = order
		@discountValue = discountValue
	end
	
	def generateDiscountVoucher
		@voucherId = order.first.customer.documentNum + Time.now.to_i.to_s + discountValue.to_s		
		# Save voucher on DB here
	end
end

class ChoiceMenu
  def self.get
	
	# WARNING: Use only product types
	# physicItem, service, book, digitalMedia	
    @choice = [["Smartphone Apple iPhone 8", "physicItem", 3500.00], 
				["Serviço de higenização de aparelho", "service", 25.00], 
				["Livro Mudando de Hábito", "book", 35.00], 
				["Filme Os Gardiões da Galáxia", "digitalMedia", 29.90]]
  end
end

# I'm use Interactive Ruby for tests
if __FILE__ == $0

	# Get menu options
	choicesMenu = ChoiceMenu.get
	
	puts "\nDigite uma das opções de produtos abaixo para gerar o pedido:"
	puts "\n"
	
	# Put options on console
	choicesMenu.each_with_index {|menu, index| puts "  #{index + 1} - #{menu[0]} => Valor(R$): #{format("%.2f", menu[2])}" }	
	
	# Set this order option from input
	choice = gets
		
	begin
		# Check if option exists
		if !choicesMenu[choice.to_i - 1].nil? and choice.to_i > 0
			#puts choicesMenu[choice.to_i - 1]
			invoiced = CreateOrderAndInvoice.new(productChoice: choicesMenu[choice.to_i - 1])
			invoiced.run			
		else
			raise ArgumentError.new("A opção é inválida. Tente novamente.")
		end
	end
end