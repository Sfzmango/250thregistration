# lib/tasks/registration.rake
require 'httparty'
require 'nokogiri'
require 'faker'
require 'securerandom'
require 'json'
require 'uri'
require 'timeout'
require 'brotli'
require 'selenium-webdriver'
require 'csv'

# Store registration data
$registration_data = []

namespace :load_test do
  desc "Export registration data to CSV"
  task :export_data do
    timestamp = Time.now.strftime("%Y%m%d_%H%M%S")
    filename = "registration_data_#{timestamp}.csv"
    
    CSV.open(filename, "wb") do |csv|
      # Write headers
      csv << ["Timestamp", "First Name", "Last Name", "Email", "Phone", "ZIP", "State", "Registration GUID", "Final URL"]
      
      # Write data
      $registration_data.each do |data|
        csv << [
          data[:timestamp],
          data[:first_name],
          data[:last_name],
          data[:email],
          data[:phone],
          data[:zip],
          data[:state],
          data[:registration_guid],
          data[:final_url]
        ]
      end
    end
    
    puts "✅ Registration data exported to #{filename}"
  end

  desc "Simulate user registrations"
  task :simulate_registrations do
    # Constants
    USER_AGENT = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/137.0.0.0 Safari/537.36'
    MAX_RETRIES = 3
    RETRY_DELAY = 5
    CAPTCHA_API_KEY = "b05191d5f2a9a2e8c59f2a6e11430066"
    NUM_OF_REGISTRATIONS = 3
    CAPTCHA_TIMEOUT = 60 # seconds
    CAPTCHA_POLL_INTERVAL = 5 # seconds
    SESSION_DELAY = 15 # seconds between requests

    NUM_OF_REGISTRATIONS.times do |i|
      puts "\n===> Registering user #{i + 1}"
      retries = 0

      begin
        # Configure Chrome options
        options = Selenium::WebDriver::Chrome::Options.new
        options.add_argument('--headless')
        options.add_argument('--disable-gpu')
        options.add_argument('--no-sandbox')
        options.add_argument('--window-size=1400,900')
        options.add_argument("--user-agent=#{USER_AGENT}")

        # Initialize the driver
        driver = Selenium::WebDriver.for :chrome, options: options
        wait = Selenium::WebDriver::Wait.new(timeout: 60)

        # Navigate to the registration page
        form_url = 'https://events.america250.org/events/250th-anniversary-of-the-us-army-grand-military-parade-and-celebration'
        driver.navigate.to form_url

        # Wait for the form to load
        wait.until { driver.find_element(css: 'form') }

        # Generate random user data
        first_name = Faker::Name.first_name
        last_name = Faker::Name.last_name
        email = "#{Faker::Internet.username(specifier: "#{first_name}#{last_name}")}@gmail.com"
        phone = Faker::PhoneNumber.subscriber_number(length: 10)
        zip = Faker::Address.zip_code
        state = 'CA'

        # Fill out the form
        puts "  -> Filling out registration form for #{email}..."

        # First Name
        first_name_field = wait.until { driver.find_element(css: 'input[name="first_name"]') }
        first_name_field.click
        first_name_field.clear
        first_name_field.send_keys(first_name)

        # Last Name
        last_name_field = wait.until { driver.find_element(css: 'input[name="last_name"]') }
        last_name_field.click
        last_name_field.clear
        last_name_field.send_keys(last_name)

        # Email
        email_field = wait.until { driver.find_element(css: 'input[name="email"]') }
        email_field.click
        email_field.clear
        email_field.send_keys(email)

        # Phone
        phone_field = wait.until { driver.find_element(css: 'input[name="phone"]') }
        phone_field.click
        phone_field.clear
        phone_field.send_keys(phone)

        # ZIP
        zip_field = wait.until { driver.find_element(css: 'input[name="zip"]') }
        zip_field.click
        zip_field.clear
        zip_field.send_keys(zip)

        # State
        state_select = wait.until { driver.find_element(css: 'select[name="state"]') }
        select = Selenium::WebDriver::Support::Select.new(state_select)
        select.select_by(:value, state)

        # Opt-in checkbox
        optin_checkbox = wait.until { driver.find_element(css: 'input[name="optin"]') }
        driver.execute_script("arguments[0].checked = true; arguments[0].dispatchEvent(new Event('change'));", optin_checkbox)

        # Get the reCAPTCHA site key
        sitekey = wait.until { driver.find_element(css: 'div.g-recaptcha') }.attribute('data-sitekey')
        puts "  -> Found reCAPTCHA sitekey: #{sitekey}"

        # Solve reCAPTCHA
        puts "  -> Solving CAPTCHA..."
        start_time = Time.now
        
        captcha_response = HTTParty.post("http://2captcha.com/in.php", query: {
          key: CAPTCHA_API_KEY,
          method: 'userrecaptcha',
          googlekey: sitekey,
          pageurl: form_url,
          json: 1
        }).parsed_response

        unless captcha_response["status"] == 1
          raise "Failed to submit CAPTCHA: #{captcha_response["request"]}"
        end

        captcha_id = captcha_response["request"]
        puts "  -> CAPTCHA submitted successfully, ID: #{captcha_id}"
        puts "  -> Waiting for solution (timeout: #{CAPTCHA_TIMEOUT}s)..."

        captcha_token = nil
        begin
          Timeout.timeout(CAPTCHA_TIMEOUT) do
            loop do
              poll = HTTParty.get("http://2captcha.com/res.php", query: {
                key: CAPTCHA_API_KEY,
                action: 'get',
                id: captcha_id,
                json: 1
              }).parsed_response

              if poll["status"] == 1
                captcha_token = poll["request"]
                elapsed_time = Time.now - start_time
                puts "  -> CAPTCHA solved successfully in #{elapsed_time.round(2)} seconds"
                break
              else
                elapsed_time = Time.now - start_time
                puts "  -> Still waiting for CAPTCHA solution... (#{elapsed_time.round(2)}s elapsed)"
                sleep CAPTCHA_POLL_INTERVAL
              end
            end
          end
        rescue Timeout::Error
          elapsed_time = Time.now - start_time
          puts "  ❌ CAPTCHA solving timed out after #{elapsed_time.round(2)} seconds"
          raise "CAPTCHA solving timed out after #{CAPTCHA_TIMEOUT} seconds"
        end

        # Set the reCAPTCHA response
        driver.execute_script("document.getElementById('g-recaptcha-response').innerHTML = '#{captcha_token}';")

        # Submit the form - using the input[type="submit"] selector with data-test attribute
        submit_button = wait.until { driver.find_element(css: 'input[data-test="ticket-selection-continue"]') }
        driver.execute_script("arguments[0].click();", submit_button)

        # Wait for redirect and extract registration GUID
        wait.until { driver.current_url.include?('/signups/') }
        registration_url = driver.current_url
        registration_guid = registration_url.split('/signups/').last.split('/').first
        puts "  -> Registration successful! GUID: #{registration_guid}"

        # Wait for the Save button on the tickets page
        begin
          save_button = wait.until { driver.find_element(css: 'input[type="submit"][value="Save"]') }
          puts "  -> Found Save button, clicking..."
          driver.execute_script("arguments[0].click();", save_button)
          
          # Wait for any success message or redirect
          sleep 2
          final_url = driver.current_url
          puts "  -> Final URL after Save: #{final_url}"
        rescue Selenium::WebDriver::Error::TimeoutError
          puts "  -> Could not find Save button on tickets page"
          final_url = driver.current_url
        end

        # Store registration data
        $registration_data << {
          timestamp: Time.now,
          first_name: first_name,
          last_name: last_name,
          email: email,
          phone: phone,
          zip: zip,
          state: state,
          registration_guid: registration_guid,
          final_url: final_url
        }

        # Close the browser
        driver.quit

      rescue => e
        puts "❌ Error: #{e.message}"
        driver&.quit
        retries += 1
        if retries <= MAX_RETRIES
          puts "  -> Retrying (#{retries}/#{MAX_RETRIES})..."
          sleep RETRY_DELAY
          retry
        else
          puts "❌ Failed after #{MAX_RETRIES} retries: #{e.message}"
        end
      end
    end
  end
end
