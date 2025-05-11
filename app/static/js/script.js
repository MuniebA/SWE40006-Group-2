// Student Registration System - JavaScript Functions

document.addEventListener("DOMContentLoaded", function () {
	// Activate all tooltips
	var tooltipTriggerList = [].slice.call(
		document.querySelectorAll('[data-bs-toggle="tooltip"]'),
	);
	var tooltipList = tooltipTriggerList.map(function (tooltipTriggerEl) {
		return new bootstrap.Tooltip(tooltipTriggerEl);
	});

	// Auto-dismiss alerts after 5 seconds
	setTimeout(function () {
		var alerts = document.querySelectorAll(".alert:not(.alert-permanent)");
		alerts.forEach(function (alert) {
			var bsAlert = new bootstrap.Alert(alert);
			bsAlert.close();
		});
	}, 5000);

	// Toggle password visibility in password fields
	const togglePasswordButtons = document.querySelectorAll(".toggle-password");
	togglePasswordButtons.forEach((button) => {
		button.addEventListener("click", function () {
			const passwordField = document.querySelector(
				this.getAttribute("data-target"),
			);
			const type =
				passwordField.getAttribute("type") === "password" ? "text" : "password";
			passwordField.setAttribute("type", type);

			// Toggle eye icon
			this.querySelector("i").classList.toggle("fa-eye");
			this.querySelector("i").classList.toggle("fa-eye-slash");
		});
	});

	// Class registration form: Filter classes by day
	const dayFilter = document.getElementById("day-filter");
	if (dayFilter) {
		dayFilter.addEventListener("change", function () {
			const selectedDay = this.value;
			const classRows = document.querySelectorAll(".class-row");

			classRows.forEach((row) => {
				if (selectedDay === "all" || row.dataset.day === selectedDay) {
					row.style.display = "";
				} else {
					row.style.display = "none";
				}
			});
		});
	}

	// Time validation for class form
	const startTimeInput = document.getElementById("start_time");
	const endTimeInput = document.getElementById("end_time");
	if (startTimeInput && endTimeInput) {
		endTimeInput.addEventListener("change", function () {
			if (startTimeInput.value && endTimeInput.value) {
				const start = new Date(`2000-01-01T${startTimeInput.value}`);
				const end = new Date(`2000-01-01T${endTimeInput.value}`);

				if (end <= start) {
					endTimeInput.setCustomValidity("End time must be after start time");
					document.getElementById("time-error").textContent =
						"End time must be after start time";
					document.getElementById("time-error").style.display = "block";
				} else {
					endTimeInput.setCustomValidity("");
					document.getElementById("time-error").style.display = "none";
				}
			}
		});
	}

	// Fee calculator for registration form
	const classSelect = document.getElementById("class_id");
	const monthSelect = document.getElementById("month");
	const feeDisplay = document.getElementById("fee-display");

	if (classSelect && monthSelect && feeDisplay) {
		const updateFee = function () {
			const classId = classSelect.value;
			const month = monthSelect.value;

			if (classId && month) {
				// Make AJAX request to get fee calculation
				fetch(`/student/calculate-fee?class_id=${classId}&month=${month}`)
					.then((response) => response.json())
					.then((data) => {
						feeDisplay.textContent = `Estimated Fee: $${data.fee.toFixed(2)}`;
						feeDisplay.style.display = "block";
					})
					.catch((error) => {
						console.error("Error calculating fee:", error);
					});
			}
		};

		classSelect.addEventListener("change", updateFee);
		monthSelect.addEventListener("change", updateFee);
	}

	// Confirmation dialogs for destructive actions
	document.querySelectorAll(".confirm-action").forEach((button) => {
		button.addEventListener("click", function (e) {
			if (!confirm(this.dataset.confirmMessage || "Are you sure?")) {
				e.preventDefault();
				return false;
			}
		});
	});

	// Data table initialization (if DataTables is available)
	if (typeof $.fn.DataTable !== "undefined") {
		$(".data-table").DataTable({
			responsive: true,
			language: {
				search: "_INPUT_",
				searchPlaceholder: "Search...",
				lengthMenu: "Show _MENU_ entries per page",
				info: "Showing _START_ to _END_ of _TOTAL_ entries",
				infoEmpty: "Showing 0 to 0 of 0 entries",
				infoFiltered: "(filtered from _MAX_ total entries)",
			},
		});
	}
});

// Function to format time in 12-hour format
function formatTime(timeString) {
	const [hours, minutes] = timeString.split(":");
	const hour = parseInt(hours, 10);
	const period = hour >= 12 ? "PM" : "AM";
	const hour12 = hour % 12 || 12;

	return `${hour12}:${minutes} ${period}`;
}

// Function to validate phone number format
function validatePhone(input) {
	const phonePattern = /^0\d{9}$/;
	const errorElement = document.getElementById("phone-error");

	if (!phonePattern.test(input.value)) {
		errorElement.textContent =
			"Phone number must be 10 digits and start with 0";
		errorElement.style.display = "block";
		input.setCustomValidity("Invalid phone format");
	} else {
		errorElement.style.display = "none";
		input.setCustomValidity("");
	}
}